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
import {IWstETH} from "../../src/interface/IWstETH.sol";
import {ZapRouterProperties} from "../../src/invariants/ZapRouterProperties.sol";
import {EbtcZapRouter} from "../../src/EbtcZapRouter.sol";
import {EbtcLeverageZapRouter} from "../../src/EbtcLeverageZapRouter.sol";
import {ZapRouterActor} from "../../src/invariants/ZapRouterActor.sol";
import {IEbtcZapRouter} from "../../src/interface/IEbtcZapRouter.sol";
import {IEbtcLeverageZapRouter} from "../../src/interface/IEbtcLeverageZapRouter.sol";
import {IEbtcZapRouterBase} from "../../src/interface/IEbtcZapRouterBase.sol";
import {WstETH} from "../../src/testContracts/WstETH.sol";
import {TargetFunctionsBase} from "./TargetFunctionsBase.sol";

interface ITCRGetter {
    function getNewTCRFromCdpChange(
        uint256 _collChange,
        bool isCollIncrease,
        uint256 _debtChange,
        bool isDebtIncrease,
        uint256 _price
    ) external view returns (uint256);
}

abstract contract TargetFunctionsNoLeverage is TargetFunctionsBase {
    function setUp() public virtual {
        super._setUp();
        mockDex = new Mock1Inch(address(eBTCToken), address(collateral));
        testWeth = address(new WETH9());
        testWstEth = payable(new WstETH(address(collateral)));
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

    function _zapBefore() private {
        zapBefore.collShares = collateral.sharesOf(address(zapRouter));
        zapBefore.stEthBalance = collateral.balanceOf(address(zapRouter));
    }

    function _zapAfter() private {
        zapAfter.collShares = collateral.sharesOf(address(zapRouter));
        zapAfter.stEthBalance = collateral.balanceOf(address(zapRouter));
    }

    function openCdpWithEth(uint256 _debt, uint256 _ethBalance) public setup {
        _dealETH(zapActor, INITIAL_COLL_BALANCE);

        bool success;
        bytes memory returnData;

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

        _zapBefore();
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
        _zapAfter();

        if (!success) {
            bool valid = _isValidAdjust(_debt, true, _ethBalance, 0);

            if (_ethBalance < zapRouter.MIN_NET_STETH_BALANCE()) {
                valid = false;
            }
            
            if (valid) {
                t(success, "Call shouldn't fail");
            }
        }

        _checkZR_01();
        _checkApproval(address(zapSender));
    }

    function openCdpWithWrappedEth(
        uint256 _debt,
        uint256 _wethBalance
    ) public setup {
        _dealWETH(zapActor, INITIAL_COLL_BALANCE, true);

        bool success;
        bytes memory returnData;

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

        _zapBefore();
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
        _zapAfter();

        if (!success) {
            bool valid = _isValidAdjust(_debt, true, _wethBalance, 0);

            if (_wethBalance < zapRouter.MIN_NET_STETH_BALANCE()) {
                valid = false;
            }

            if (valid) {
                t(success, "Call shouldn't fail");
            }
        }

        _checkZR_01();
        _checkApproval(address(zapSender));
    }

    function openCdpWithWstEth(
        uint256 _debt,
        uint256 _wstEthBalance
    ) public setup {
        _dealWrappedCollateral(zapActor, INITIAL_COLL_BALANCE, true);

        bool success;
        bytes memory returnData;

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
        _wstEthBalance = IWstETH(testWstEth).getWstETHByStETH(between(
            requiredCollAmount,
            minCollAmount,
            maxCollAmount
        ));

        IEbtcZapRouterBase.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                address(zapRouter),
                zapActorKey
            );

        _zapBefore();
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
        _zapAfter();

        if (!success) {
            bool valid = _isValidAdjust(_debt, true, IWstETH(testWstEth).getStETHByWstETH(_wstEthBalance), 0);

            if (IWstETH(testWstEth).getStETHByWstETH(_wstEthBalance) < zapRouter.MIN_NET_STETH_BALANCE()) {
                valid = false;
            }

            if (valid) {
                t(success, "Call shouldn't fail");
            }
        }

        _checkZR_01();
        _checkApproval(address(zapSender));
    }

    function closeCdp(uint _i) public setup {
        bool success;
        bytes memory returnData;

        require(cdpManager.getActiveCdpsCount() > 1, "Cannot close last CDP");

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(zapSender));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(zapSender), _i);
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

        _zapBefore();
        (success, returnData) = zapActor.proxy(
            address(zapRouter),
            abi.encodeWithSelector(
                IEbtcZapRouter.closeCdp.selector,
                _cdpId,
                pmPermit
            ),
            true
        );
        _zapAfter();

        if (!success) {
            bool valid = _isValidAdjust(cdpManager.getSyncedCdpDebt(_cdpId), false, 0, 0);
            
            if (valid) {
                t(success, "Call shouldn't fail");
            }
        }

        _checkZR_01();
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
            uint256 numberOfCdps = sortedCdps.cdpCountOf(address(zapSender));
            require(numberOfCdps > 0, "Actor must have at least one CDP open");

            _i = between(_i, 0, numberOfCdps - 1);
            _cdpId = sortedCdps.cdpOfOwnerByIndex(address(zapSender), _i);
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

        _zapBefore();
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
        _zapAfter();

        bool valid = _isValidAdjust(
            _debtChange, 
            _isDebtIncrease,
            _stEthBalanceIncrease,
            _stEthBalanceDecrease
        );

        if (valid) {
            t(success, "Call shouldn't fail");
        }

        _checkZR_01();
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
            uint256 numberOfCdps = sortedCdps.cdpCountOf(address(zapSender));
            require(numberOfCdps > 0, "Actor must have at least one CDP open");

            _i = between(_i, 0, numberOfCdps - 1);
            _cdpId = sortedCdps.cdpOfOwnerByIndex(address(zapSender), _i);
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

        _zapBefore();
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
        _zapAfter();

        bool valid = _isValidAdjust(
            _debtChange, 
            _isDebtIncrease,
            _wethBalanceIncrease,
            _stEthBalanceDecrease
        );

        if (valid) {
            t(success, "Call shouldn't fail");
        }

        _checkZR_01();
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
            uint256 numberOfCdps = sortedCdps.cdpCountOf(address(zapSender));
            require(numberOfCdps > 0, "Actor must have at least one CDP open");

            _i = between(_i, 0, numberOfCdps - 1);
            _cdpId = sortedCdps.cdpOfOwnerByIndex(address(zapSender), _i);
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

            _wstEthBalanceIncrease = IWstETH(testWstEth).getWstETHByStETH(min(
                _wstEthBalanceIncrease,
                (INITIAL_COLL_BALANCE / 10) - entireColl
            ));
        }

        IEbtcZapRouterBase.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                address(zapRouter),
                zapActorKey
            );

        _zapBefore();
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
        _zapAfter();

        bool valid = _isValidAdjust(
            _debtChange, 
            _isDebtIncrease,
            IWstETH(testWstEth).getStETHByWstETH(_wstEthBalanceIncrease),
            _stEthBalanceDecrease
        );

        if (valid) {
            t(success, "Call shouldn't fail");
        }

        _checkZR_01();
        _checkApproval(address(zapSender));
    }

    function _checkZR_01() private {
        lte(
            zapAfter.stEthBalance - zapBefore.stEthBalance,
            MAX_COLL_ROUNDING_ERROR,
            ZR_01
        );
        lte(
            zapAfter.collShares - zapBefore.collShares,
            MAX_COLL_ROUNDING_ERROR,
            ZR_01
        );
    }

    function _isValidAdjust(
        uint256 _debtChange, 
        bool _isDebtIncrease,
        uint256 _stEthBalanceIncrease,
        uint256 _stEthBalanceDecrease
    ) private view returns (bool) {
        if (_debtChange > 0 && _debtChange < zapRouter.MIN_CHANGE()) {
            return false;         
        }
        if (_stEthBalanceIncrease > 0 && _stEthBalanceDecrease > 0) {
            return false;
        }
        if (_stEthBalanceIncrease > 0 && _stEthBalanceIncrease < zapRouter.MIN_CHANGE()) {
            return false;
        }
        if (_stEthBalanceDecrease > 0 && _stEthBalanceDecrease < zapRouter.MIN_CHANGE()) {
            return false;
        }
        uint price = priceFeedMock.getPrice();

        uint256 tcr = ITCRGetter(address(borrowerOperations)).getNewTCRFromCdpChange(
            _stEthBalanceIncrease > 0 ? _stEthBalanceIncrease : _stEthBalanceDecrease,
            _stEthBalanceIncrease > 0,
            _debtChange,
            _isDebtIncrease,
            price
        );

        if (tcr < borrowerOperations.CCR()) {
            return false;
        }

        return true;
    }
}
