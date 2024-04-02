// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/Hevm.sol";
import {TargetContractSetup} from "@ebtc/contracts/TestContracts/invariants/TargetContractSetup.sol";
import {CollateralTokenTester} from "@ebtc/contracts/TestContracts/CollateralTokenTester.sol";
import {Mock1Inch} from "@ebtc/contracts/TestContracts/Mock1Inch.sol";
import {ICdpManager} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IBorrowerOperations, IPositionManagers} from "@ebtc/contracts/LeverageMacroBase.sol";
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

abstract contract TargetFunctionsNoLeverage is TargetFunctionsBase {
    function setUp() public virtual {
        super._setUp();
        mockDex = new Mock1Inch(address(eBTCToken), address(collateral));
        testWeth = address(new WETH9());
        testWstEth = address(new WstETH(address(collateral)));
        zapRouter = new EbtcZapRouter(
            IERC20(testWstEth),
            IERC20(testWeth),
            IStETH(address(collateral)),
            IERC20(address(eBTCToken)),
            IBorrowerOperations(address(borrowerOperations)),
            ICdpManager(address(cdpManager)),
            defaultGovernance
        );
    }

    function openCdpWithEth(uint256 _debt, uint256 _ethBalance) public setup {
        _dealETH(zapActor, INITIAL_COLL_BALANCE);

        bool success;
        bytes memory returnData;

        // TODO: Figure out the best way to clamp this
        // Is clamping necessary? Can we just let it revert?
        _debt = between(_debt, 1, 0.1e18);

        // we pass in CCR instead of MCR in case it's the first one
        uint price = priceFeedMock.getPrice();

        uint256 requiredCollAmount = (_debt * cdpManager.CCR()) / (price);
        uint256 minCollAmount = max(
            cdpManager.MIN_NET_STETH_BALANCE() +
                borrowerOperations.LIQUIDATOR_REWARD(),
            requiredCollAmount
        );
        uint256 maxCollAmount = min(
            2 * minCollAmount,
            INITIAL_COLL_BALANCE / 10
        );
        _ethBalance = between(requiredCollAmount, minCollAmount, maxCollAmount);

        IEbtcZapRouterBase.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                address(zapRouter),
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

    function openCdpWithWrappedEth(
        uint256 _debt,
        uint256 _wethBalance
    ) public setup {
        _dealWETH(zapActor, INITIAL_COLL_BALANCE, true);

        bool success;
        bytes memory returnData;

        // TODO: Figure out the best way to clamp this
        // Is clamping necessary? Can we just let it revert?
        _debt = between(_debt, 1, 0.1e18);

        // we pass in CCR instead of MCR in case it's the first one
        uint price = priceFeedMock.getPrice();

        uint256 requiredCollAmount = (_debt * cdpManager.CCR()) / (price);
        uint256 minCollAmount = max(
            cdpManager.MIN_NET_STETH_BALANCE() +
                borrowerOperations.LIQUIDATOR_REWARD(),
            requiredCollAmount
        );
        uint256 maxCollAmount = min(
            2 * minCollAmount,
            INITIAL_COLL_BALANCE / 10
        );
        _wethBalance = between(
            requiredCollAmount,
            minCollAmount,
            maxCollAmount
        );

        IEbtcZapRouterBase.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                address(zapRouter),
                zapActorKey
            );

        (success, returnData) = zapActor.proxy(
            address(zapRouter),
            abi.encodeWithSelector(
                IEbtcZapRouter.openCdpWithWrappedEth.selector,
                _debt,
                bytes32(0),
                bytes32(0),
                _wethBalance,
                pmPermit
            ),
            true
        );
        t(success, "Call shouldn't fail");

        _checkApproval(address(zapSender));
    }

    function openCdpWithWstEth(
        uint256 _debt,
        uint256 _wstEthBalance
    ) public setup {
        _dealWrappedCollateral(zapActor, INITIAL_COLL_BALANCE, true);

        bool success;
        bytes memory returnData;

        // TODO: Figure out the best way to clamp this
        // Is clamping necessary? Can we just let it revert?
        _debt = between(_debt, 1, 0.1e18);

        // we pass in CCR instead of MCR in case it's the first one
        uint price = priceFeedMock.getPrice();

        uint256 requiredCollAmount = (_debt * cdpManager.CCR()) / (price);
        uint256 minCollAmount = max(
            cdpManager.MIN_NET_STETH_BALANCE() +
                borrowerOperations.LIQUIDATOR_REWARD(),
            requiredCollAmount
        );
        uint256 maxCollAmount = min(
            2 * minCollAmount,
            INITIAL_COLL_BALANCE / 10
        );
        _wstEthBalance = between(
            requiredCollAmount,
            minCollAmount,
            maxCollAmount
        );

        IEbtcZapRouterBase.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                address(zapRouter),
                zapActorKey
            );

        (success, returnData) = zapActor.proxy(
            address(zapRouter),
            abi.encodeWithSelector(
                IEbtcZapRouter.openCdpWithWstEth.selector,
                _debt,
                bytes32(0),
                bytes32(0),
                _wstEthBalance,
                pmPermit
            ),
            true
        );
        t(success, "Call shouldn't fail");

        _checkApproval(address(zapSender));
    }

    function closeCdp(uint _i) public setup {
        bool success;
        bytes memory returnData;

        require(cdpManager.getActiveCdpsCount() > 1, "Cannot close last CDP");

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        t(
            _cdpId != bytes32(0),
            "CDP ID must not be null if the index is valid"
        );

        IEbtcZapRouterBase.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                address(zapRouter),
                zapActorKey
            );

        (success, returnData) = zapActor.proxy(
            address(zapRouter),
            abi.encodeWithSelector(
                IEbtcZapRouter.closeCdp.selector,
                _cdpId,
                pmPermit
            ),
            true
        );
        t(success, "Call shouldn't fail");

        _checkApproval(address(zapSender));
    }

    function adjustCdp(
        uint _i,
        uint _stEthBalanceDecrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _stEthBalanceIncrease,
        bool _useWstETHForDecrease
    ) public setup {
        _dealCollateral(zapActor, INITIAL_COLL_BALANCE, true);

        bool success;
        bytes memory returnData;
        bytes32 _cdpId;

        {
            uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
            require(numberOfCdps > 0, "Actor must have at least one CDP open");

            _i = between(_i, 0, numberOfCdps - 1);
            _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
            t(
                _cdpId != bytes32(0),
                "CDP ID must not be null if the index is valid"
            );
        }

        {
            (uint256 entireDebt, uint256 entireColl) = cdpManager
                .getSyncedDebtAndCollShares(_cdpId);
            _stEthBalanceDecrease = between(
                _stEthBalanceDecrease,
                0,
                entireColl
            );
            _debtChange = between(_debtChange, 0, entireDebt);

            _stEthBalanceIncrease = min(
                _stEthBalanceIncrease,
                (INITIAL_COLL_BALANCE / 10) - entireColl
            );
        }

        IEbtcZapRouterBase.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                address(zapRouter),
                zapActorKey
            );

        (success, returnData) = zapActor.proxy(
            address(zapRouter),
            abi.encodeWithSelector(
                IEbtcZapRouter.adjustCdp.selector,
                _cdpId,
                _stEthBalanceDecrease,
                _debtChange,
                _isDebtIncrease,
                bytes32(0),
                bytes32(0),
                _stEthBalanceIncrease,
                _useWstETHForDecrease,
                pmPermit
            ),
            true
        );
        t(success, "Call shouldn't fail");

        _checkApproval(address(zapSender));
    }

    function adjustCdpWithWrappedEth(
        uint _i,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        uint256 _wethBalanceIncrease,
        bool _useWstETHForDecrease
    ) public setup {
        _dealWETH(zapActor, INITIAL_COLL_BALANCE, true);

        bool success;
        bytes memory returnData;
        bytes32 _cdpId;

        {
            uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
            require(numberOfCdps > 0, "Actor must have at least one CDP open");

            _i = between(_i, 0, numberOfCdps - 1);
            _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
            t(
                _cdpId != bytes32(0),
                "CDP ID must not be null if the index is valid"
            );
        }

        {
            (uint256 entireDebt, uint256 entireColl) = cdpManager
                .getSyncedDebtAndCollShares(_cdpId);
            _stEthBalanceDecrease = between(
                _stEthBalanceDecrease,
                0,
                entireColl
            );
            _debtChange = between(_debtChange, 0, entireDebt);

            _wethBalanceIncrease = min(
                _wethBalanceIncrease,
                (INITIAL_COLL_BALANCE / 10) - entireColl
            );
        }

        IEbtcZapRouterBase.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                address(zapRouter),
                zapActorKey
            );

        (success, returnData) = zapActor.proxy(
            address(zapRouter),
            abi.encodeWithSelector(
                IEbtcZapRouter.adjustCdpWithWrappedEth.selector,
                _cdpId,
                _stEthBalanceDecrease,
                _debtChange,
                _isDebtIncrease,
                bytes32(0),
                bytes32(0),
                _wethBalanceIncrease,
                _useWstETHForDecrease,
                pmPermit
            ),
            true
        );
        t(success, "Call shouldn't fail");

        _checkApproval(address(zapSender));
    }

    function adjustCdpWithWstEth(
        uint _i,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        uint256 _wstEthBalanceIncrease,
        bool _useWstETHForDecrease
    ) public setup {
        _dealWrappedCollateral(zapActor, INITIAL_COLL_BALANCE, true);

        bool success;
        bytes memory returnData;
        bytes32 _cdpId;

        {
            uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
            require(numberOfCdps > 0, "Actor must have at least one CDP open");

            _i = between(_i, 0, numberOfCdps - 1);
            _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
            t(
                _cdpId != bytes32(0),
                "CDP ID must not be null if the index is valid"
            );
        }

        {
            (uint256 entireDebt, uint256 entireColl) = cdpManager
                .getSyncedDebtAndCollShares(_cdpId);
            _stEthBalanceDecrease = between(
                _stEthBalanceDecrease,
                0,
                entireColl
            );
            _debtChange = between(_debtChange, 0, entireDebt);

            _wstEthBalanceIncrease = min(
                _wstEthBalanceIncrease,
                (INITIAL_COLL_BALANCE / 10) - entireColl
            );
        }

        IEbtcZapRouterBase.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                address(zapRouter),
                zapActorKey
            );

        (success, returnData) = zapActor.proxy(
            address(zapRouter),
            abi.encodeWithSelector(
                IEbtcZapRouter.adjustCdpWithWrappedEth.selector,
                _cdpId,
                _stEthBalanceDecrease,
                _debtChange,
                _isDebtIncrease,
                bytes32(0),
                bytes32(0),
                _wstEthBalanceIncrease,
                _useWstETHForDecrease,
                pmPermit
            ),
            true
        );
        t(success, "Call shouldn't fail");

        _checkApproval(address(zapSender));
    }
}
