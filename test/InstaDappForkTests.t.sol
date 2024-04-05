// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {EbtcZapRouter} from "../src/EbtcZapRouter.sol";
import {ZapRouterBaseInvariants} from "./ZapRouterBaseInvariants.sol";
import {IERC3156FlashLender} from "@ebtc/contracts/Interfaces/IERC3156FlashLender.sol";
import {IBorrowerOperations, IPositionManagers} from "@ebtc/contracts/LeverageMacroBase.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IPriceFeed} from "@ebtc/contracts/Interfaces/IPriceFeed.sol";
import {IEbtcZapRouter} from "../src/interface/IEbtcZapRouter.sol";
import {IEbtcLeverageZapRouter, IEbtcLeverageZapRouterBase} from "../src/interface/IEbtcLeverageZapRouter.sol";
import {IEbtcZapRouterBase} from "../src/interface/IEbtcZapRouterBase.sol";
import {ConnectV2BadgerZapRouter} from "../src/connector/main.sol";

interface IConnectorV2Registry {
    function addConnectors(string[] calldata _connectorNames, address[] calldata _connectors) external;
}

interface IDSAAccount {
    function cast(
        string[] calldata _targetNames,
        bytes[] calldata _datas,
        address _origin
    ) external;
}

contract InstaDappForkTests is ZapRouterBaseInvariants {
    address public instaMaster;
    IDSAAccount public testDSA;
    address public dsaOwner;
    IConnectorV2Registry public connectorRegistry;
    ConnectV2BadgerZapRouter public zapConnector;
    IPriceFeed public priceFeed;

    function setUp() public override {
        super.setUp();

        instaMaster = 0x2386DC45AdDed673317eF068992F19421B481F4c;
        connectorRegistry = IConnectorV2Registry(0x97b0B3A8bDeFE8cB9563a3c610019Ad10DB8aD11);
        priceFeed = IPriceFeed(0xa9a65B1B1dDa8376527E89985b221B6bfCA1Dc9a);
        zapConnector = new ConnectV2BadgerZapRouter(IEbtcLeverageZapRouterBase.DeploymentParams({
            borrowerOperations: 0xd366e016Ae0677CdCE93472e603b75051E022AD0,
            activePool: 0x6dBDB6D420c110290431E863A1A978AE53F69ebC,
            cdpManager: 0xc4cbaE499bb4Ca41E78f52F07f5d98c375711774,
            ebtc: 0x661c70333AA1850CcDBAe82776Bb436A0fCfeEfB,
            stEth: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            wstEth: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            sortedCdps: 0x591AcB5AE192c147948c12651a0a5f24f0529BE3,
            priceFeed: address(priceFeed),
            dex: 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
        }));
        testDSA = IDSAAccount(0x66Ac88DC71F3d8D1dD7E8572BCE70b25C5895C29);
        dsaOwner = 0x6Eb9d3dc07d5a10c3a0B561A6a375536F322def4;

        string[] memory connectorNames = new string[](1);
        address[] memory connectors = new address[](1);

        connectorNames[0] = zapConnector.name();
        connectors[0] = address(zapConnector);

        vm.prank(instaMaster);
        connectorRegistry.addConnectors(connectorNames, connectors);
    }

    function _getOpenCdpTradeData(uint256 _debt, uint256 expectedMinOut) 
        private returns (IEbtcLeverageZapRouter.TradeData memory) {
        return IEbtcLeverageZapRouterBase.TradeData({
            performSwapChecks: true,
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

        uint256 debt = 1e18;
        uint256 flAmount = _debtToCollateral(debt);
        uint256 marginAmount = 5 ether;

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(address(testDSA), dsaOwner);

        targetNames[0] = zapConnector.name();
        datas[0] = abi.encodeWithSelector(
            zapConnector.openCdp.selector,
            debt,
            bytes32(0),
            bytes32(0),
            flAmount,
            marginAmount,
            (flAmount + marginAmount) * COLLATERAL_BUFFER / SLIPPAGE_PRECISION,
            pmPermit,
            _getOpenCdpTradeData(debt, flAmount)           
        );

        testDSA.cast(targetNames, datas, 0x03d70891b8994feB6ccA7022B25c32be92ee3725);
    }
}
