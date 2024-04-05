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
import {IERC3156FlashLender} from "@ebtc/contracts/Interfaces/IERC3156FlashLender.sol";
import {IStETH} from "../../src/interface/IStETH.sol";
import {ZapRouterProperties} from "../../src/invariants/ZapRouterProperties.sol";
import {EbtcZapRouter} from "../../src/EbtcZapRouter.sol";
import {EbtcLeverageZapRouter} from "../../src/EbtcLeverageZapRouter.sol";
import {ZapRouterActor} from "../../src/invariants/ZapRouterActor.sol";
import {IEbtcZapRouter} from "../../src/interface/IEbtcZapRouter.sol";
import {IEbtcLeverageZapRouter, IEbtcLeverageZapRouterBase} from "../../src/interface/IEbtcLeverageZapRouter.sol";
import {IEbtcZapRouterBase} from "../../src/interface/IEbtcZapRouterBase.sol";
import {WstETH} from "../../src/testContracts/WstETH.sol";
import {TargetFunctionsBase} from "./TargetFunctionsBase.sol";
import "forge-std/console2.sol";

abstract contract TargetFunctionsWithLeverage is TargetFunctionsBase {
    uint256 public constant MAXIMUM_DEBT = 1e27;
    uint256 public constant MAXIMUM_COLL = 2000000 ether;
    uint256 internal constant SLIPPAGE_PRECISION = 1e4;
    /// @notice Collateral buffer used to account for slippage and fees
    /// 9995 = 0.05%
    uint256 internal constant COLLATERAL_BUFFER = 9995;

    function setUp() public virtual {
        super._setUp();
        mockDex = new Mock1Inch(address(eBTCToken), address(collateral));
        testWeth = address(new WETH9());
        testWstEth = address(new WstETH(address(collateral)));
        leverageZapRouter = new EbtcLeverageZapRouter(
            IEbtcLeverageZapRouterBase.DeploymentParams({
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
            })
        );
    }

    function _debtToCollateral(uint256 _debt) public returns (uint256) {
        uint256 price = priceFeedMock.fetchPrice();
        return (_debt * 1e18) / price;
    }

    function _collateralToDebt(uint256 _coll) public returns (uint256) {
        uint256 price = priceFeedMock.fetchPrice();
        return (_coll * price) / 1e18;
    }

    function _seedActivePoolAndDex(uint256 _seedAmount) internal {
        // Give stETH to active pool
        _dealCollateral(zapActor, _seedAmount, false);

        bool success;
        bytes memory returnData;

        (success, returnData) = zapActor.proxy(
            address(collateral),
            abi.encodeWithSelector(CollateralTokenTester.transfer.selector, activePool, _seedAmount),
            false
        );
        t(success, "transfer cannot fail");

        // Give stETH to mock DEX
        _dealCollateral(zapActor, _seedAmount, false);

        (success, returnData) = zapActor.proxy(
            address(collateral),
            abi.encodeWithSelector(CollateralTokenTester.transfer.selector, mockDex, _seedAmount),
            false
        );
        t(success, "transfer cannot fail");
    }

    function openCdp(uint256 _debt, uint256 _marginAmount) public setup {
        _debt = between(_debt, 1000, MAXIMUM_DEBT);

        uint256 flAmount = _debtToCollateral(_debt);
        uint256 minCollAmount = cdpManager.MIN_NET_STETH_BALANCE() +
            borrowerOperations.LIQUIDATOR_REWARD();

        if (flAmount < minCollAmount) {
            flAmount = minCollAmount;
            _debt = _collateralToDebt(flAmount);
        }

        if (flAmount > MAXIMUM_COLL) {
            flAmount = MAXIMUM_COLL;
            _debt = _collateralToDebt(flAmount);
        }

        if (_marginAmount > MAXIMUM_COLL - flAmount) {
            _marginAmount = MAXIMUM_COLL - flAmount;
        }

        _seedActivePoolAndDex(flAmount);

        _dealCollateral(zapActor, _marginAmount, true);

        uint256 totalDeposit = ((flAmount + _marginAmount) * COLLATERAL_BUFFER) / SLIPPAGE_PRECISION;

        bool success;
        bytes memory returnData;

        (success, returnData) = _openCdp(_debt, flAmount, _marginAmount, totalDeposit);

        if (!success) {
            uint256 cr = hintHelpers.computeCR(totalDeposit, _debt, priceFeedMock.fetchPrice());

            t(cr < borrowerOperations.MCR(), ZR_07);
        }

        _checkApproval(address(leverageZapRouter));
    }

    function _openCdp(
        uint256 _debt,
        uint256 _flAmount,
        uint256 _marginAmount,
        uint256 _totalAmount
    ) internal returns (bool success, bytes memory returnData) {
        return
            zapActor.proxy(
                address(leverageZapRouter),
                _encodeOpenParams(_debt, _flAmount, _marginAmount, _totalAmount),
                true
            );
    }

    function _encodeOpenParams(
        uint256 _debt,
        uint256 _flAmount,
        uint256 _marginAmount,
        uint256 _totalAmount
    ) internal returns (bytes memory) {
        IEbtcZapRouterBase.PositionManagerPermit memory pmPermit = _generateOneTimePermit(
            address(zapSender),
            address(leverageZapRouter),
            zapActorKey
        );

        return
            abi.encodeWithSelector(
                IEbtcLeverageZapRouter.openCdp.selector,
                _debt,
                bytes32(0),
                bytes32(0),
                _flAmount,
                _marginAmount,
                _totalAmount,
                pmPermit,
                _encodeOpenTrade(_debt)
            );
    }

    function _encodeOpenTrade(uint256 _debt) internal returns (bytes memory) {
        return
            abi.encodeWithSelector(
                mockDex.swap.selector,
                address(eBTCToken),
                address(collateral),
                _debt // Debt amount
            );
    }

    function closeCdp(uint _i, uint256 _maxSlippage) public setup {
        bool success;
        bytes memory returnData;

        require(cdpManager.getActiveCdpsCount() > 1, "Cannot close last CDP");

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(zapSender));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(zapSender), _i);
        t(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        IEbtcZapRouterBase.PositionManagerPermit memory pmPermit = _generateOneTimePermit(
            address(zapSender),
            address(leverageZapRouter),
            zapActorKey
        );

        uint256 debt = cdpManager.getSyncedCdpDebt(_cdpId);

        uint256 flashFee = IERC3156FlashLender(address(borrowerOperations)).flashFee(
            address(eBTCToken),
            debt
        );

        (success, returnData) = zapActor.proxy(
            address(leverageZapRouter),
            abi.encodeWithSelector(
                IEbtcLeverageZapRouter.closeCdp.selector,
                _cdpId,
                pmPermit,
                (_debtToCollateral(debt + flashFee) * _maxSlippage) / SLIPPAGE_PRECISION,
                abi.encodeWithSelector(
                    mockDex.swapExactOut.selector,
                    address(collateral),
                    address(eBTCToken),
                    debt + flashFee
                )
            ),
            true
        );
        t(success, "Call shouldn't fail");

        _checkApproval(address(leverageZapRouter));
    }

    function adjustCdp(
        uint _i,
        uint256 _debtChange,
        bool _isDebtIncrease,
        uint256 _marginChange,
        bool isMarginIncrease
    ) public setup {
        require(cdpManager.getActiveCdpsCount() > 1, "Cannot close last CDP");

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(zapSender));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(zapSender), _i);
        t(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        (uint256 debt, uint256 coll) = cdpManager.getSyncedDebtAndCollShares(_cdpId);
        
        if (_isDebtIncrease) {
            debt += _debtChange;

            if (debt > MAXIMUM_DEBT) {
                _debtChange = MAXIMUM_DEBT - debt;
            }

            uint256 collValue = _debtToCollateral(debt);

            if (collValue > MAXIMUM_COLL) {
                _debtChange = _collateralToDebt(MAXIMUM_COLL) - debt;
            }

            uint256 apBal = collateral.balanceOf(address(activePool));

            if (collValue > apBal) {
                _seedActivePoolAndDex(collValue - apBal);
            }
        }

        if (isMarginIncrease) {
            uint256 totalColl = _marginChange + coll;
            if (totalColl > MAXIMUM_COLL) {
                _marginChange = MAXIMUM_COLL - coll;
            }

            _dealCollateral(zapActor, _marginChange, true);
        }

        IEbtcZapRouterBase.PositionManagerPermit memory pmPermit = _generateOneTimePermit(
            address(zapSender),
            address(leverageZapRouter),
            zapActorKey
        );

        bool success;
        bytes memory returnData;

        if (_isDebtIncrease) {
            (success, returnData) = _adjustCdpDebtIncrease(_cdpId, _debtChange, _marginChange);
        } else {
            (success, returnData) = _adjustCdpDebtDecrease(_cdpId, _debtChange, _marginChange);
        }

        if (!success) {
            if (_debtChange > borrowerOperations.MIN_CHANGE()) {
                t(success, "Call shouldn't fail");
            }    
        }

        _checkApproval(address(leverageZapRouter));
    }

    function _adjustCdpDebtIncrease(
        bytes32 _cdpId,
        uint256 _debtChange,
        uint256 _marginChange
    ) internal returns (bool success, bytes memory returnData) {
        IEbtcZapRouterBase.PositionManagerPermit memory pmPermit = _generateOneTimePermit(
            address(zapSender),
            address(leverageZapRouter),
            zapActorKey
        );

        uint256 collValue = (_debtToCollateral(_debtChange) * 9995) / 10000;

        (success, returnData) = zapActor.proxy(
            address(leverageZapRouter),
            abi.encodeWithSelector(
                IEbtcLeverageZapRouter.adjustCdp.selector,
                _cdpId,
                IEbtcLeverageZapRouterBase.AdjustCdpParams({
                    flashLoanAmount: _debtToCollateral(_debtChange),
                    debtChange: _debtChange,
                    isDebtIncrease: true,
                    upperHint: bytes32(0),
                    lowerHint: bytes32(0),
                    stEthBalanceChange: collValue,
                    isStEthBalanceIncrease: true,
                    stEthMarginBalance: _marginChange,
                    isStEthMarginIncrease: true,
                    useWstETHForDecrease: false
                }),
                pmPermit,
                abi.encodeWithSelector(
                    mockDex.swap.selector,
                    address(eBTCToken),
                    address(collateral),
                    _debtChange // Debt amount
                )
            ),
            true
        );
    }

    function _adjustCdpDebtDecrease(
        bytes32 _cdpId,
        uint256 _debtChange,
        uint256 _marginChange
    ) internal returns (bool success, bytes memory returnData) {
        IEbtcZapRouterBase.PositionManagerPermit memory pmPermit = _generateOneTimePermit(
            address(zapSender),
            address(leverageZapRouter),
            zapActorKey
        );

        uint256 collValue = (_debtToCollateral(_debtChange) * 10003) / 10000 + 1;

        (success, returnData) = zapActor.proxy(
            address(leverageZapRouter),
            abi.encodeWithSelector(
                IEbtcLeverageZapRouter.adjustCdp.selector,
                _cdpId,
                IEbtcLeverageZapRouterBase.AdjustCdpParams({
                    flashLoanAmount: _debtChange,
                    debtChange: _debtChange,
                    isDebtIncrease: false,
                    upperHint: bytes32(0),
                    lowerHint: bytes32(0),
                    stEthBalanceChange: collValue,
                    isStEthBalanceIncrease: false,
                    stEthMarginBalance: _marginChange,
                    isStEthMarginIncrease: false,
                    useWstETHForDecrease: false
                }),
                pmPermit,
                abi.encodeWithSelector(
                    mockDex.swap.selector,
                    address(collateral),
                    address(eBTCToken),
                    collValue // Debt amount
                )
            ),
            true
        );
    }
}
