// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/Hevm.sol";
import {TargetContractSetup} from "@ebtc/contracts/TestContracts/invariants/TargetContractSetup.sol";
import {CollateralTokenTester} from "@ebtc/contracts/TestContracts/CollateralTokenTester.sol";
import {Mock1Inch} from "@ebtc/contracts/TestContracts/Mock1Inch.sol";
import {ICdpManager} from "@ebtc/contracts/interfaces/ICdpManager.sol";
import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {WETH9} from "@ebtc/contracts/TestContracts/WETH9.sol";
import {IStETH} from "../../src/interface/IStETH.sol";
import {ZapRouterProperties} from "../../src/invariants/ZapRouterProperties.sol";
import {EbtcZapRouter} from "../../src/EbtcZapRouter.sol";
import {EbtcLeverageZapRouter} from "../../src/EbtcLeverageZapRouter.sol";
import {ZapRouterActor} from "../../src/invariants/ZapRouterActor.sol";
import {IEbtcZapRouter} from "../../src/interface/IEbtcZapRouter.sol";
import {IEbtcLeverageZapRouter} from "../../src/interface/IEbtcLeverageZapRouter.sol";
import {IEbtcZapRouterBase} from "../../src/interface/IEbtcZapRouterBase.sol";
import {WstETH} from "../../src/testContracts/WstETH.sol";
import {TargetFunctionsBase} from "./TargetFunctionsBase.sol";

abstract contract TargetFunctionsWithLeverage is TargetFunctionsBase {
    function setUp() public virtual {
        super._setUp();
        mockDex = new Mock1Inch(address(eBTCToken), address(collateral));
        testWeth = address(new WETH9());
        testWstEth = address(new WstETH(address(collateral)));
        leverageZapRouter = new EbtcLeverageZapRouter(IEbtcLeverageZapRouter.DeploymentParams({
            borrowerOperations: address(borrowerOperations),
            activePool: address(activePool),
            cdpManager: address(cdpManager),
            ebtc: address(eBTCToken),
            stEth: address(collateral),
            weth: address(testWeth),
            wstEth: address(testWstEth),
            sortedCdps: address(sortedCdps),
            priceFeed: address(priceFeedMock),
            dex: address(mockDex)
        }));
    }

    function openCdp(
        uint256 _debt,
        uint256 _stEthBalance
    ) public setup {
        _dealCollateral(zapActor);

        bool success;
        bytes memory returnData;

        // TODO: Figure out the best way to clamp this
        // Is clamping necessary? Can we just let it revert?
        _debt = between(_debt, 1, 0.1e18);

       IEbtcZapRouterBase.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                zapActorKey
            );

        (success, returnData) = zapActor.proxy(
            address(zapRouter),
            abi.encodeWithSelector(
                IEbtcZapRouter.openCdpWithEth.selector,
                _debt,
                bytes32(0),
                bytes32(0),
                _ethBalance,
                pmPermit
            ),
            _ethBalance,
            true
        );
        t(success, "Call shouldn't fail");

        _checkApproval(address(zapSender));
        
    }
}
