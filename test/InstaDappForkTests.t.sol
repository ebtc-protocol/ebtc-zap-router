// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {EbtcLeverageZapRouter} from "../src/EbtcLeverageZapRouter.sol";
import {ZapRouterBaseInvariants} from "./ZapRouterBaseInvariants.sol";
import {IERC3156FlashLender} from "@ebtc/contracts/Interfaces/IERC3156FlashLender.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {Mock1Inch} from "@ebtc/contracts/TestContracts/Mock1Inch.sol";
import {IBorrowerOperations, IPositionManagers} from "@ebtc/contracts/LeverageMacroBase.sol";
import {BorrowerOperations} from "@ebtc/contracts/BorrowerOperations.sol";
import {CdpManager} from "@ebtc/contracts/CdpManager.sol";
import {SortedCdps} from "@ebtc/contracts/SortedCdps.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IPriceFeed} from "@ebtc/contracts/Interfaces/IPriceFeed.sol";
import {IEbtcZapRouter} from "../src/interface/IEbtcZapRouter.sol";
import {IEbtcLeverageZapRouter, IEbtcLeverageZapRouterBase} from "../src/interface/IEbtcLeverageZapRouter.sol";
import {IEbtcZapRouterBase} from "../src/interface/IEbtcZapRouterBase.sol";
import {ConnectorV2BadgerZapRouter} from "../src/connector/main.sol";
import {IDSAAccount} from "../src/interface/IDSAAccount.sol";

interface IConnectorV2Registry {
    function addConnectors(string[] calldata _connectorNames, address[] calldata _connectors) external;
}

contract InstaDappForkTests is Test {
    uint256 internal constant SLIPPAGE_PRECISION = 1e4;
    /// @notice Collateral buffer used to account for slippage and fees
    /// 9995 = 0.05%
    uint256 internal constant COLLATERAL_BUFFER = 9995;
    uint256 internal constant deadline = 1800;

    address public instaMaster;
    IDSAAccount public testDSA;
    address public dsaOwner;
    address public testUser;
    uint256 public userPrivateKey;
    IConnectorV2Registry public connectorRegistry;
    ConnectorV2BadgerZapRouter public zapConnector;
    BorrowerOperations public borrowerOperations;
    CdpManager public cdpManager;
    IPriceFeed public priceFeed;
    IERC20 public collateral;
    IERC20 public eBTCToken;
    SortedCdps public sortedCdps;
    Mock1Inch public mockDex;
    EbtcLeverageZapRouter public zapRouter;

    function setUp() public {

        userPrivateKey = 0x12345;
        testUser = vm.addr(userPrivateKey);

        instaMaster = 0x2386DC45AdDed673317eF068992F19421B481F4c;
        connectorRegistry = IConnectorV2Registry(0x97b0B3A8bDeFE8cB9563a3c610019Ad10DB8aD11);
        collateral = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        eBTCToken = IERC20(0x661c70333AA1850CcDBAe82776Bb436A0fCfeEfB);
        sortedCdps = SortedCdps(0x591AcB5AE192c147948c12651a0a5f24f0529BE3);
        priceFeed = IPriceFeed(0xa9a65B1B1dDa8376527E89985b221B6bfCA1Dc9a);
        borrowerOperations = BorrowerOperations(0xd366e016Ae0677CdCE93472e603b75051E022AD0);
        cdpManager = CdpManager(0xc4cbaE499bb4Ca41E78f52F07f5d98c375711774);
        testDSA = IDSAAccount(0x66Ac88DC71F3d8D1dD7E8572BCE70b25C5895C29);
        dsaOwner = 0x6Eb9d3dc07d5a10c3a0B561A6a375536F322def4;

        // Create and fund mock dex
        mockDex = new Mock1Inch(address(eBTCToken), address(collateral));
        mockDex.setPrice(priceFeed.fetchPrice());
        vm.prank(0xc8D45CC670c6485F70528976D65f7603160Be2CD);
        collateral.transfer(address(mockDex), 1000e18);
        vm.prank(0xba15E9b644685cB845aF18a738Abd40C6Bcd78eD);
        eBTCToken.transfer(address(mockDex), 1e18);

        // fund DSA wallet
        vm.prank(0xc8D45CC670c6485F70528976D65f7603160Be2CD);
        collateral.transfer(address(testDSA), 1e18);

        zapRouter = new EbtcLeverageZapRouter(IEbtcLeverageZapRouterBase.DeploymentParams({
            borrowerOperations: address(borrowerOperations),
            activePool: 0x6dBDB6D420c110290431E863A1A978AE53F69ebC,
            cdpManager: address(cdpManager),
            ebtc: address(eBTCToken),
            stEth: address(collateral),
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            wstEth: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            sortedCdps: address(sortedCdps),
            dex: address(mockDex)
        }));

        zapConnector = new ConnectorV2BadgerZapRouter(
            address(zapRouter), 
            address(borrowerOperations), 
            address(collateral)
        );

        string[] memory connectorNames = new string[](1);
        address[] memory connectors = new address[](1);

        connectorNames[0] = zapConnector.name();
        connectors[0] = address(zapConnector);

        vm.prank(instaMaster);
        connectorRegistry.addConnectors(connectorNames, connectors);
    }

    function _addAuthUser(address user) private {
        string[] memory targetNames = new string[](1);
        bytes[] memory datas = new bytes[](1);

        targetNames[0] = "AUTHORITY-A";
        datas[0] = abi.encodeWithSelector(
            0x0a3b0a4f, //function add(address)
            user
        );

        vm.prank(dsaOwner);
        testDSA.cast(targetNames, datas, 0x03d70891b8994feB6ccA7022B25c32be92ee3725);
    }

    function _getOpenCdpTradeData(uint256 _debt, uint256 expectedMinOut) 
        private returns (IEbtcLeverageZapRouter.TradeData memory) {
        return IEbtcLeverageZapRouterBase.TradeData({
            performSwapChecks: false,
            expectedMinOut: expectedMinOut,
            exchangeData: abi.encodeWithSelector(
                mockDex.swap.selector,
                address(eBTCToken),
                address(collateral),
                _debt // Debt amount
            )
        });
    }

    function _debtToCollateral(uint256 _debt) public returns (uint256) {
        uint256 price = priceFeed.fetchPrice();
        return (_debt * 1e18) / price;
    }

    function testOpenLevCdpWithStEth() public {
        string[] memory targetNames = new string[](3);
        bytes[] memory datas = new bytes[](3);

        uint256 debt = 0.1e18;
        uint256 flAmount = _debtToCollateral(debt);
        uint256 marginAmount = 1 ether;
        uint256 depositAmount = (flAmount + marginAmount) * COLLATERAL_BUFFER / SLIPPAGE_PRECISION;

        targetNames[0] = zapConnector.name();
        targetNames[1] = zapConnector.name();
        targetNames[2] = zapConnector.name();

        datas[0] = abi.encodeWithSelector(
            zapConnector.setPositionManagerApproval.selector
        );
        datas[1] = abi.encodeWithSelector(
            zapConnector.openCdp.selector,
            debt,
            bytes32(0),
            bytes32(0),
            flAmount,
            marginAmount,
            depositAmount,
            _getOpenCdpTradeData(debt, flAmount),
            0,
            0        
        );
        datas[2] = abi.encodeWithSelector(
            zapConnector.revokePositionManagerApproval.selector
        );

        vm.prank(dsaOwner);
        testDSA.cast(targetNames, datas, 0x03d70891b8994feB6ccA7022B25c32be92ee3725);
    }

    function testCloseLevCdp() public {
        testOpenLevCdpWithStEth();

        bytes32 cdpId = sortedCdps.toCdpId(address(testDSA), block.number, sortedCdps.nextCdpNonce() - 1);

        uint256 debt = cdpManager.getSyncedCdpDebt(cdpId);
        uint256 flashFee = IERC3156FlashLender(address(borrowerOperations)).flashFee(
            address(eBTCToken),
            debt
        );

        uint256 _maxSlippage = 10050; // 0.5% slippage

        assertEq(cdpManager.getCdpStatus(cdpId), uint256(ICdpManagerData.Status.active));
        
        uint256 flAmount = _debtToCollateral(debt + flashFee);
        string[] memory targetNames = new string[](3);
        bytes[] memory datas = new bytes[](3);

        targetNames[0] = zapConnector.name();
        targetNames[1] = zapConnector.name();
        targetNames[2] = zapConnector.name();

        datas[0] = abi.encodeWithSelector(
            zapConnector.setPositionManagerApproval.selector
        );
        datas[1] = abi.encodeWithSelector(
            zapConnector.closeCdp.selector,
            cdpId,
            (flAmount * _maxSlippage) / SLIPPAGE_PRECISION, 
            IEbtcLeverageZapRouterBase.TradeData({
                performSwapChecks: true,
                expectedMinOut: 0,
                exchangeData: abi.encodeWithSelector(
                    mockDex.swapExactOut.selector,
                    address(collateral),
                    address(eBTCToken),
                    debt + flashFee
                )
            }),
            0,
            0     
        );
        datas[2] = abi.encodeWithSelector(
            zapConnector.revokePositionManagerApproval.selector
        );

        vm.prank(dsaOwner);
        testDSA.cast(targetNames, datas, 0x03d70891b8994feB6ccA7022B25c32be92ee3725);        
    }

    function testAdjustLevCdpIncreaseDebt() public {

    }

    function testAdjustLevCdpDecreaseDebt() public {
        
    }
}
