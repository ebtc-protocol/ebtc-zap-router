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
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IPriceFeed} from "@ebtc/contracts/Interfaces/IPriceFeed.sol";
import {IEbtcZapRouter} from "../src/interface/IEbtcZapRouter.sol";
import {IEbtcLeverageZapRouter, IEbtcLeverageZapRouterBase} from "../src/interface/IEbtcLeverageZapRouter.sol";
import {IEbtcZapRouterBase} from "../src/interface/IEbtcZapRouterBase.sol";
import {ConnectV2BadgerZapRouter} from "../src/connector/main.sol";
import {IDSAAccount} from "../src/interface/IDSAAccount.sol";
import {EbtcFlashLoanReceiver} from "../src/connector/EbtcFlashLoanReceiver.sol";

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
    ConnectV2BadgerZapRouter public zapConnector;
    BorrowerOperations public borrowerOperations;
    IPriceFeed public priceFeed;
    IERC20 public collateral;
    IERC20 public eBTCToken;
    address public sortedCdps;
    Mock1Inch public mockDex;
    EbtcFlashLoanReceiver public flashLoanReceiver;

    function setUp() public {

        userPrivateKey = 0x12345;
        testUser = vm.addr(userPrivateKey);

        instaMaster = 0x2386DC45AdDed673317eF068992F19421B481F4c;
        connectorRegistry = IConnectorV2Registry(0x97b0B3A8bDeFE8cB9563a3c610019Ad10DB8aD11);
        collateral = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        eBTCToken = IERC20(0x661c70333AA1850CcDBAe82776Bb436A0fCfeEfB);
        sortedCdps = 0x591AcB5AE192c147948c12651a0a5f24f0529BE3;
        priceFeed = IPriceFeed(0xa9a65B1B1dDa8376527E89985b221B6bfCA1Dc9a);
        borrowerOperations = BorrowerOperations(0xd366e016Ae0677CdCE93472e603b75051E022AD0);
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

        flashLoanReceiver = new EbtcFlashLoanReceiver(
            address(borrowerOperations),
            0x6dBDB6D420c110290431E863A1A978AE53F69ebC, // activePool
            0xc4cbaE499bb4Ca41E78f52F07f5d98c375711774, // cdpManager
            address(eBTCToken),
            address(collateral),
            sortedCdps,
            false // _sweepToCaller
        );

        zapConnector = new ConnectV2BadgerZapRouter(
            address(flashLoanReceiver), 
            address(borrowerOperations), 
            address(collateral),
            address(eBTCToken),
            address(sortedCdps),
            address(mockDex) //0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
        );

        _addAuthUser(address(flashLoanReceiver));

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

    function _createUserFromPrivateKey(
        uint256 _privateKey
    ) internal returns (address user) {
        user = vm.addr(_privateKey);
    }

    function createPermit(
        address target,
        address user
    ) internal returns (IEbtcZapRouter.PositionManagerPermit memory pmPermit) {
        uint _deadline = (block.timestamp + deadline);
        IPositionManagers.PositionManagerApproval _approval = IPositionManagers
            .PositionManagerApproval
            .OneTime;

        vm.startPrank(user);

        // Generate signature to one-time approve zap
        bytes32 digest = _generatePermitSignature(user, target, _approval, _deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        pmPermit = IEbtcZapRouterBase.PositionManagerPermit(_deadline, v, r, s);

        vm.stopPrank();
    }

    function _generatePermitSignature(
        address _signer,
        address _positionManager,
        IPositionManagers.PositionManagerApproval _approval,
        uint _deadline
    ) internal returns (bytes32) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                borrowerOperations.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        borrowerOperations.permitTypeHash(),
                        _signer,
                        _positionManager,
                        _approval,
                        borrowerOperations.nonces(_signer),
                        _deadline
                    )
                )
            )
        );
        return digest;
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

    function testLevCdpWithStEth() public {
        string[] memory targetNames = new string[](1);
        bytes[] memory datas = new bytes[](1);

        uint256 debt = 0.1e18;
        uint256 flAmount = _debtToCollateral(debt);
        uint256 marginAmount = 1 ether;

//        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(address(zapRouter), testUser);

        targetNames[0] = zapConnector.name();
        datas[0] = abi.encodeWithSelector(
            zapConnector.openCdp.selector,
            debt,
            bytes32(0),
            bytes32(0),
            flAmount,
            marginAmount,
            (flAmount + marginAmount) * COLLATERAL_BUFFER / SLIPPAGE_PRECISION,
            _getOpenCdpTradeData(debt, flAmount)           
        );

        vm.prank(dsaOwner);
        testDSA.cast(targetNames, datas, 0x03d70891b8994feB6ccA7022B25c32be92ee3725);
    }
}
