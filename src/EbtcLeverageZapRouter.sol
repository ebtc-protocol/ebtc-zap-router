// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC3156FlashLender} from "@ebtc/contracts/Interfaces/IERC3156FlashLender.sol";
import {LeverageZapRouterBase} from "./LeverageZapRouterBase.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManagerData.sol";
import {ICdpManager} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IBorrowerOperations} from "@ebtc/contracts/Interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/Interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {SafeERC20} from "@ebtc/contracts/Dependencies/SafeERC20.sol";
import {EbtcBase} from "@ebtc/contracts/Dependencies/EbtcBase.sol";
import {IStETH} from "./interface/IStETH.sol";
import {IWrappedETH} from "./interface/IWrappedETH.sol";
import {IEbtcLeverageZapRouter} from "./interface/IEbtcLeverageZapRouter.sol";
import {IWstETH} from "./interface/IWstETH.sol";

contract EbtcLeverageZapRouter is LeverageZapRouterBase {
    using SafeERC20 for IERC20;

    constructor(
        IEbtcLeverageZapRouter.DeploymentParams memory params
    ) LeverageZapRouterBase(params) { }

    /// @dev Open a CDP with raw native Ether
    /// @param _debt The total expected debt for new CDP
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _stEthLoanAmount The flash loan amount needed to open the leveraged Cdp position
    /// @param _ethMarginBalance The amount of margin deposit (converted from raw Ether) from the user, higher margin equals lower CR
    /// @param _stEthDepositAmount The total stETH collateral amount deposited (added) for the specified Cdp
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    /// @param _tradeData DEX calldata for converting between debt and collateral
    function openCdpWithEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _ethMarginBalance,
        uint256 _stEthDepositAmount,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external payable returns (bytes32 cdpId) {
        uint256 _collVal = _convertRawEthToStETH(_ethMarginBalance);

        cdpId = _openCdp(
            _debt,
            _upperHint,
            _lowerHint,
            _stEthLoanAmount,
            _collVal,
            _stEthDepositAmount,
            _positionManagerPermit,
            _tradeData
        );

        emit ZapOperationEthVariant(
            cdpId,
            EthVariantZapOperationType.OpenCdp,
            true,
            NATIVE_ETH_ADDRESS,
            _ethMarginBalance,
            _collVal,
            msg.sender
        );
    }

    /// @dev Open a CDP with wrapped staked Ether
    /// @param _debt The total expected debt for new CDP
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _stEthLoanAmount The flash loan amount needed to open the leveraged Cdp position
    /// @param _wstEthMarginBalance The amount of margin deposit (converted from wrapped stETH) from the user, higher margin equals lower CR
    /// @param _stEthDepositAmount The total stETH collateral amount deposited (added) for the specified Cdp
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    /// @param _tradeData DEX calldata for converting between debt and collateral
    function openCdpWithWstEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _wstEthMarginBalance,
        uint256 _stEthDepositAmount,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external returns (bytes32 cdpId) {
        uint256 _collVal = _convertWstEthToStETH(_wstEthMarginBalance);

        cdpId = _openCdp(
            _debt,
            _upperHint,
            _lowerHint,
            _stEthLoanAmount,
            _collVal,
            _stEthDepositAmount,
            _positionManagerPermit,
            _tradeData
        );

        emit ZapOperationEthVariant(
            cdpId,
            EthVariantZapOperationType.OpenCdp,
            true,
            address(wstEth),
            _wstEthMarginBalance,
            _collVal,
            msg.sender
        );
    }

    /// @dev This is to allow wrapped ETH related Zap
    receive() external payable {
        require(
            msg.sender == address(wrappedEth),
            "EbtcLeverageZapRouter: only allow Wrapped ETH to send Ether!"
        );
    }

    /// @dev Open a CDP with wrapped Ether
    /// @param _debt The total expected debt for new CDP
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _stEthLoanAmount The flash loan amount needed to open the leveraged Cdp position
    /// @param _wethMarginBalance The amount of margin deposit (converted from wrapped Ether) from the user, higher margin equals lower CR
    /// @param _stEthDepositAmount The total stETH collateral amount deposited (added) for the specified Cdp
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    /// @param _tradeData DEX calldata for converting between debt and collateral
    function openCdpWithWrappedEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _wethMarginBalance,
        uint256 _stEthDepositAmount,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external returns (bytes32 cdpId) {
        uint256 _collVal = _convertWrappedEthToStETH(_wethMarginBalance);

        cdpId = _openCdp(
            _debt,
            _upperHint,
            _lowerHint,
            _stEthLoanAmount,
            _collVal,
            _stEthDepositAmount,
            _positionManagerPermit,
            _tradeData
        );

        emit ZapOperationEthVariant(
            cdpId,
            EthVariantZapOperationType.OpenCdp,
            true,
            address(wrappedEth),
            _wethMarginBalance,
            _collVal,
            msg.sender
        );
    }

    /// @dev Open a CDP with staked Ether
    /// @param _debt The total expected debt for new CDP
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _stEthLoanAmount The flash loan amount needed to open the leveraged Cdp position
    /// @param _stEthMarginAmount The amount of margin deposit (converted from staked Ether) from the user, higher margin equals lower CR
    /// @param _stEthDepositAmount The total stETH collateral amount deposited (added) for the specified Cdp
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    /// @param _tradeData DEX calldata for converting between debt and collateral
    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _stEthMarginAmount,
        uint256 _stEthDepositAmount,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external returns (bytes32 cdpId) {
        uint256 _collVal = _transferInitialStETHFromCaller(_stEthMarginAmount);

        cdpId = _openCdp(
            _debt,
            _upperHint,
            _lowerHint,
            _stEthLoanAmount,
            _collVal,
            _stEthDepositAmount,
            _positionManagerPermit,
            _tradeData
        );

        emit ZapOperationEthVariant(
            cdpId,
            EthVariantZapOperationType.OpenCdp,
            true,
            address(stEth),
            _stEthMarginAmount,
            _collVal,
            msg.sender
        );
    }

    function _openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _stEthMarginAmount,
        uint256 _stEthDepositAmount,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) internal nonReentrant returns (bytes32 cdpId) {
        
        _requireZeroOrMinAdjustment(_debt);
        _requireAtLeastMinNetStEthBalance(_stEthDepositAmount - LIQUIDATOR_REWARD);

        // _positionManagerPermit is only required if called directly
        // for 3rd party integrations (i.e. DeFi saver, instadapp), setPositionManagerApproval
        // can be used before and after each operation
        if (_positionManagerPermit.length > 0) {
            PositionManagerPermit memory approval = abi.decode(_positionManagerPermit, (PositionManagerPermit));
            _permitPositionManagerApproval(borrowerOperations, approval);
        }

        // pre-compute cdpId for post checks
        cdpId = sortedCdps.toCdpId(msg.sender, block.number, sortedCdps.nextCdpNonce());

        OpenCdpForOperation memory cdp;

        cdp.eBTCToMint = _debt;
        cdp._upperHint = _upperHint;
        cdp._lowerHint = _lowerHint;
        cdp.stETHToDeposit = _stEthDepositAmount;
        cdp.borrower = msg.sender;

        _openCdpOperation({
            _cdpId: cdpId,
            _cdp: cdp,
            _flAmount: _stEthLoanAmount,
            _tradeData: _tradeData
        });

        if (_positionManagerPermit.length > 0) {
            borrowerOperations.renouncePositionManagerApproval(msg.sender);
        }
    }

    /// @dev Close a CDP with original collateral(stETH) returned to CDP owner
    /// @dev Note plain collateral(stETH) is returned no matter whatever asset is zapped in
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    /// @param _tradeData DEX calldata for converting between debt and collateral
    function closeCdp(
        bytes32 _cdpId,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external {
        _closeCdp(_cdpId, _positionManagerPermit, false, _tradeData);
    }

    /// @dev Close a CDP with wrapped version of collateral(WstETH) returned to CDP owner
    /// @dev Note plain collateral(stETH) is returned no matter whatever asset is zapped in
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    /// @param _tradeData DEX calldata for converting between debt and collateral
    function closeCdpForWstETH(
        bytes32 _cdpId,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external {
        _closeCdp(_cdpId, _positionManagerPermit, true, _tradeData);
    }

    function _closeCdp(
        bytes32 _cdpId,
        bytes calldata _positionManagerPermit,
        bool _useWstETH,
        TradeData calldata _tradeData
    ) internal nonReentrant {
        require(msg.sender == _getOwnerAddress(_cdpId), "EbtcLeverageZapRouter: not owner for close!");

        uint256 debt = ICdpManager(address(cdpManager)).getSyncedCdpDebt(_cdpId);

        // _positionManagerPermit is only required if called directly
        // for 3rd party integrations (i.e. DeFi saver, instadapp), setPositionManagerApproval
        // can be used before and after each operation
        if (_positionManagerPermit.length > 0) {
            PositionManagerPermit memory approval = abi.decode(_positionManagerPermit, (PositionManagerPermit));
            _permitPositionManagerApproval(borrowerOperations, approval);
        }

        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        _closeCdpOperation({
            _cdpId: _cdpId,
            _debt: debt,
            _tradeData: _tradeData
        });
        uint256 _zapStEthBalanceAfter = stEth.balanceOf(address(this));
        uint256 _stETHDiff = _zapStEthBalanceAfter - _zapStEthBalanceBefore;

        if (_positionManagerPermit.length > 0) {
            borrowerOperations.renouncePositionManagerApproval(msg.sender);
        }

        _transferStEthToCaller(_cdpId, EthVariantZapOperationType.CloseCdp, _useWstETH, _stETHDiff);
    }

    function _requireNonZeroAdjustment(
        uint256 _stEthBalanceIncrease,
        uint256 _debtChange,
        uint256 _stEthBalanceDecrease
    ) internal pure {
        require(
            _stEthBalanceIncrease > 0 || _stEthBalanceDecrease > 0 || _debtChange > 0,
            "BorrowerOperations: There must be either a collateral or debt change"
        );
    }

    function _requireSingularMarginChange(
        uint256 _stEthMarginIncrease,
        uint256 _stEthMarginDecrease
    ) internal pure {
        require(
            _stEthMarginIncrease == 0 || _stEthMarginDecrease == 0,
            "EbtcLeverageZapRouter: Cannot add and withdraw margin in same operation"
        );
    }

    /// @notice Function that allows various operations which might change both collateral (increase collateral with raw native Ether) and debt of a Cdp
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _params Parameters used for the adjust Cdp operation
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    /// @param _tradeData DEX calldata for converting between debt and collateral
    function adjustCdpWithEth(
        bytes32 _cdpId,
        AdjustCdpParams memory _params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external payable {
        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        if (_params.isStEthMarginIncrease && _params.stEthMarginBalance > 0) {
            _params.stEthMarginBalance = _convertRawEthToStETH(_params.stEthMarginBalance);
        }
        _adjustCdp(_cdpId, _params, _positionManagerPermit, _tradeData, _zapStEthBalanceBefore);
    }

    /// @notice Function that allows various operations which might change both collateral (increase collateral with wrapped Ether) and debt of a Cdp
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _params Parameters used for the adjust Cdp operation
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    /// @param _tradeData DEX calldata for converting between debt and collateral
    function adjustCdpWithWstEth(
        bytes32 _cdpId,
        AdjustCdpParams memory _params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external {
        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        if (_params.isStEthMarginIncrease && _params.stEthMarginBalance > 0) {
            _params.stEthMarginBalance = _convertWstEthToStETH(_params.stEthMarginBalance);
        }
        _adjustCdp(_cdpId, _params, _positionManagerPermit, _tradeData, _zapStEthBalanceBefore);
    }

    /// @notice Function that allows various operations which might change both collateral (increase collateral with wrapped Ether) and debt of a Cdp
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _params Parameters used for the adjust Cdp operation
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    /// @param _tradeData DEX calldata for converting between debt and collateral
    function adjustCdpWithWrappedEth(
        bytes32 _cdpId,
        AdjustCdpParams memory _params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external {
        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        if (_params.isStEthMarginIncrease && _params.stEthMarginBalance > 0) {
            _params.stEthMarginBalance = _convertWrappedEthToStETH(_params.stEthMarginBalance);
        }
        _adjustCdp(_cdpId, _params, _positionManagerPermit, _tradeData, _zapStEthBalanceBefore);
    }

    /// @notice Function that allows various operations which might change both collateral and debt of a Cdp
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _params Parameters used for the adjust Cdp operation
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    /// @param _tradeData DEX calldata for converting between debt and collateral
    function adjustCdp(
        bytes32 _cdpId,
        AdjustCdpParams memory _params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external {
        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        if (_params.isStEthMarginIncrease && _params.stEthMarginBalance > 0) {
            _params.stEthMarginBalance = _transferInitialStETHFromCaller(_params.stEthMarginBalance);
        }
        _adjustCdp(_cdpId, _params, _positionManagerPermit, _tradeData, _zapStEthBalanceBefore);
    }

    function _adjustCdp(
        bytes32 _cdpId,
        AdjustCdpParams memory _params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData,
        uint256 _zapStEthBalanceBefore
    ) internal nonReentrant {
        require(msg.sender == _getOwnerAddress(_cdpId), "EbtcLeverageZapRouter: not owner for adjust!");
        _requireZeroOrMinAdjustment(_params.debtChange);
        _requireZeroOrMinAdjustment(_params.stEthBalanceChange);
        _requireZeroOrMinAdjustment(_params.stEthMarginBalance);

        // get debt and coll amounts for post checks
        (uint256 debt, uint256 coll) = ICdpManager(address(cdpManager)).getSyncedDebtAndCollShares(_cdpId);

        if (_positionManagerPermit.length > 0) {
            PositionManagerPermit memory approval = abi.decode(_positionManagerPermit, (PositionManagerPermit));
            _permitPositionManagerApproval(borrowerOperations, approval);
        }
        
        uint256 marginDecrease = _params.isStEthBalanceIncrease ? 0 : _params.stEthBalanceChange;
        if (!_params.isStEthMarginIncrease && _params.stEthMarginBalance > 0) {
            marginDecrease += _params.stEthMarginBalance;
        }

        uint256 marginIncrease = _params.isStEthBalanceIncrease ? _params.stEthBalanceChange : 0;
        if (_params.isStEthMarginIncrease && _params.stEthMarginBalance > 0) {
            marginIncrease += _params.stEthMarginBalance;
        }

        _requireNonZeroAdjustment(marginIncrease, _params.debtChange, marginDecrease);
        _requireSingularMarginChange(marginIncrease, marginDecrease);

        _adjustCdpOperation({
            _cdpId: _cdpId,
            _flType: _params.isDebtIncrease ? FlashLoanType.stETH : FlashLoanType.eBTC,
            _flAmount: _params.flashLoanAmount,
            _cdp: AdjustCdpOperation({
                _cdpId: _cdpId,
                _EBTCChange: _params.debtChange,
                _isDebtIncrease: _params.isDebtIncrease,
                _upperHint: _params.upperHint,
                _lowerHint: _params.lowerHint,
                _stEthBalanceIncrease: marginIncrease,
                _stEthBalanceDecrease: marginDecrease
            }),
            debt: debt,
            coll: coll,
            _tradeData: _tradeData
        });
        uint256 _zapStEthBalanceDiff = stEth.balanceOf(address(this)) - _zapStEthBalanceBefore;

        if (_positionManagerPermit.length > 0) {
            borrowerOperations.renouncePositionManagerApproval(msg.sender);
        }

        if (_zapStEthBalanceDiff > 0) {
            _transferStEthToCaller(
                _cdpId,
                EthVariantZapOperationType.AdjustCdp,
                _params.useWstETHForDecrease,
                _zapStEthBalanceDiff
            );
        }
    }
}
