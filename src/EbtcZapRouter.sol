// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManagerData.sol";
import {ICdpManager} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IBorrowerOperations, IPositionManagers} from "@ebtc/contracts/LeverageMacroBase.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {SafeERC20} from "@ebtc/contracts/Dependencies/SafeERC20.sol";
import {ZapRouterBase} from "./ZapRouterBase.sol";
import {IStETH} from "./interface/IStETH.sol";
import {IWrappedETH} from "./interface/IWrappedETH.sol";
import {IEbtcZapRouter} from "./interface/IEbtcZapRouter.sol";
import {IWstETH} from "./interface/IWstETH.sol";

contract EbtcZapRouter is ZapRouterBase, IEbtcZapRouter {
    using SafeERC20 for IERC20;

    IERC20 public immutable ebtc;
    IBorrowerOperations public immutable borrowerOperations;
    ICdpManager public immutable cdpManager;
    address public immutable owner;

    constructor(
        IERC20 _wstEth,
        IERC20 _wEth,
        IStETH _stEth,
        IERC20 _ebtc,
        IBorrowerOperations _borrowerOperations,
        ICdpManager _cdpManager,
        address _owner
    ) ZapRouterBase(address(_borrowerOperations), _wstEth, _wEth, _stEth) {
        ebtc = _ebtc;
        borrowerOperations = _borrowerOperations;
        cdpManager = _cdpManager;
        owner = _owner;

        // Infinite Approvals @TODO: do these stay at max for each token?
        stEth.approve(address(borrowerOperations), type(uint256).max);
        stEth.approve(address(wstEth), type(uint256).max);
    }

    /// @dev This is to allow wrapped ETH related Zap
    receive() external payable {
        require(
            msg.sender == address(wrappedEth),
            "EbtcZapRouter: only allow Wrapped ETH to send Ether!"
        );
    }

    /// @dev Open a CDP with stEth
    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        PositionManagerPermit calldata _positionManagerPermit
    ) external returns (bytes32 cdpId) {
        uint256 _collVal = _transferInitialStETHFromCaller(_stEthBalance);

        cdpId = _openCdpWithPermit(
            _debt,
            _upperHint,
            _lowerHint,
            _collVal,
            _positionManagerPermit
        );

        emit ZapOperationEthVariant(
            cdpId,
            EthVariantZapOperationType.OpenCdp,
            true,
            address(stEth),
            _stEthBalance,
            _collVal,
            msg.sender
        );
    }

    /// @dev Open a CDP with raw native Ether
    /// @param _debt The total expected debt for new CDP
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _ethBalance The total stETH collateral (converted from raw Ether) amount deposited (added) for the specified Cdp
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function openCdpWithEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _ethBalance,
        PositionManagerPermit calldata _positionManagerPermit
    ) external payable returns (bytes32 cdpId) {
        uint256 _collVal = _convertRawEthToStETH(_ethBalance);

        cdpId = _openCdpWithPermit(_debt, _upperHint, _lowerHint, _collVal, _positionManagerPermit);

        emit ZapOperationEthVariant(
            cdpId,
            EthVariantZapOperationType.OpenCdp,
            true,
            NATIVE_ETH_ADDRESS,
            _ethBalance,
            _collVal,
            msg.sender
        );
    }

    /// @dev Open a CDP with Wrapped Ether
    /// @param _debt The total expected debt for new CDP
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _wethBalance The total stETH collateral (converted from wrapped Ether) amount deposited (added) for the specified Cdp
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function openCdpWithWrappedEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wethBalance,
        PositionManagerPermit calldata _positionManagerPermit
    ) external returns (bytes32 cdpId) {
        uint256 _collVal = _convertWrappedEthToStETH(_wethBalance);

        cdpId = _openCdpWithPermit(_debt, _upperHint, _lowerHint, _collVal, _positionManagerPermit);

        emit ZapOperationEthVariant(
            cdpId,
            EthVariantZapOperationType.OpenCdp,
            true,
            address(wrappedEth),
            _wethBalance,
            _collVal,
            msg.sender
        );
    }

    /// @dev Open a CDP with Wrapped StETH
    /// @param _debt The total expected debt for new CDP
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _wstEthBalance The total stETH collateral (converted from wrapped stETH) amount deposited (added) for the specified Cdp
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function openCdpWithWstEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wstEthBalance,
        PositionManagerPermit calldata _positionManagerPermit
    ) external returns (bytes32 cdpId) {
        uint256 _collVal = _convertWstEthToStETH(_wstEthBalance);

        cdpId = _openCdpWithPermit(_debt, _upperHint, _lowerHint, _collVal, _positionManagerPermit);

        emit ZapOperationEthVariant(
            cdpId,
            EthVariantZapOperationType.OpenCdp,
            true,
            address(wstEth),
            _wstEthBalance,
            _collVal,
            msg.sender
        );
    }

    /// @dev Close a CDP with original collateral(stETH) returned to CDP owner
    /// @dev Note plain collateral(stETH) is returned no matter whatever asset is zapped in
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function closeCdp(
        bytes32 _cdpId,
        PositionManagerPermit calldata _positionManagerPermit
    ) external {
        _closeCdpWithPermit(_cdpId, false, _positionManagerPermit);
    }

    /// @dev Close a CDP with wrapped version of collateral(WstETH) returned to CDP owner
    /// @dev Note plain collateral(stETH) is returned no matter whatever asset is zapped in
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function closeCdpForWstETH(
        bytes32 _cdpId,
        PositionManagerPermit calldata _positionManagerPermit
    ) external {
        _closeCdpWithPermit(_cdpId, true, _positionManagerPermit);
    }

    /// @notice Function that allows various operations which might change both collateral (increase collateral with raw native Ether) and debt of a Cdp
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _collBalanceDecrease The total stETH collateral amount withdrawn from the specified Cdp
    /// @param _debtChange The total eBTC debt amount withdrawn or repaid for the specified Cdp
    /// @param _isDebtIncrease The flag (true or false) to indicate whether this is a eBTC token withdrawal (debt increase) or a repayment (debt reduce)
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _ethBalanceIncrease The total stETH collateral (converted from raw native Ether) amount deposited (added) for the specified Cdp
    /// @param _useWstETHForDecrease Indicator whether withdrawn collateral is original(stETH) or wrapped version(WstETH)
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function adjustCdpWithEth(
        bytes32 _cdpId,
        uint256 _collBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _ethBalanceIncrease,
        bool _useWstETHForDecrease,
        PositionManagerPermit calldata _positionManagerPermit
    ) external payable {
        _adjustCdpWithEth(
            _cdpId,
            _collBalanceDecrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _ethBalanceIncrease,
            _useWstETHForDecrease,
            _positionManagerPermit
        );
    }

    function _adjustCdpWithEth(
        bytes32 _cdpId,
        uint256 _collBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _ethBalanceIncrease,
        bool _useWstETHForDecrease,
        PositionManagerPermit calldata _positionManagerPermit
    ) internal {
        uint256 _collBalanceIncrease = _ethBalanceIncrease;
        if (_ethBalanceIncrease > 0) {
            _collBalanceIncrease = _convertRawEthToStETH(_ethBalanceIncrease);
            emit ZapOperationEthVariant(
                _cdpId,
                EthVariantZapOperationType.AdjustCdp,
                true,
                NATIVE_ETH_ADDRESS,
                _ethBalanceIncrease,
                _collBalanceIncrease,
                msg.sender
            );
        }

        _adjustCdpWithPermit(
            _cdpId,
            _collBalanceDecrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _collBalanceIncrease,
            _useWstETHForDecrease,
            _positionManagerPermit
        );
    }

    /// @notice Function that allows various operations which might change both collateral (increase collateral with wrapped Ether) and debt of a Cdp
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _collBalanceDecrease The total stETH collateral amount withdrawn from the specified Cdp
    /// @param _debtChange The total eBTC debt amount withdrawn or repaid for the specified Cdp
    /// @param _isDebtIncrease The flag (true or false) to indicate whether this is a eBTC token withdrawal (debt increase) or a repayment (debt reduce)
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _wethBalanceIncrease The total stETH collateral (converted from wrapped Ether) amount deposited (added) for the specified Cdp
    /// @param _useWstETHForDecrease Indicator whether withdrawn collateral is original(stETH) or wrapped version(WstETH)
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function adjustCdpWithWrappedEth(
        bytes32 _cdpId,
        uint256 _collBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wethBalanceIncrease,
        bool _useWstETHForDecrease,
        PositionManagerPermit calldata _positionManagerPermit
    ) external {
        uint256 _collBalanceIncrease = _wethBalanceIncrease;
        if (_wethBalanceIncrease > 0) {
            _collBalanceIncrease = _convertWrappedEthToStETH(_wethBalanceIncrease);
            emit ZapOperationEthVariant(
                _cdpId,
                EthVariantZapOperationType.AdjustCdp,
                true,
                address(wrappedEth),
                _wethBalanceIncrease,
                _collBalanceIncrease,
                msg.sender
            );
        }

        _adjustCdpWithPermit(
            _cdpId,
            _collBalanceDecrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _collBalanceIncrease,
            _useWstETHForDecrease,
            _positionManagerPermit
        );
    }

    /// @notice Function that allows various operations which might change both collateral (increase collateral with wrapped Ether) and debt of a Cdp
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _collBalanceDecrease The total stETH collateral amount withdrawn from the specified Cdp
    /// @param _debtChange The total eBTC debt amount withdrawn or repaid for the specified Cdp
    /// @param _isDebtIncrease The flag (true or false) to indicate whether this is a eBTC token withdrawal (debt increase) or a repayment (debt reduce)
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _wstEthBalanceIncrease The total stETH collateral (converted from wrapped stETH) amount deposited (added) for the specified Cdp
    /// @param _useWstETHForDecrease Indicator whether withdrawn collateral is original(stETH) or wrapped version(WstETH)
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function adjustCdpWithWstEth(
        bytes32 _cdpId,
        uint256 _collBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wstEthBalanceIncrease,
        bool _useWstETHForDecrease,
        PositionManagerPermit calldata _positionManagerPermit
    ) external {
        uint256 _collBalanceIncrease = _wstEthBalanceIncrease;

        // wstETH In
        if (_wstEthBalanceIncrease > 0) {
            _collBalanceIncrease = _convertWstEthToStETH(_wstEthBalanceIncrease);
            emit ZapOperationEthVariant(
                _cdpId, 
                EthVariantZapOperationType.AdjustCdp, 
                true, 
                address(wstEth), 
                _wstEthBalanceIncrease, 
                _collBalanceIncrease,
                msg.sender
            );
        }

        _adjustCdpWithPermit(
            _cdpId,
            _collBalanceDecrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _collBalanceIncrease,
            _useWstETHForDecrease,
            _positionManagerPermit
        );
    }

    /// @notice Function that allows various operations which might change both collateral and debt of a Cdp
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _collBalanceDecrease The total stETH collateral amount withdrawn from the specified Cdp
    /// @param _debtChange The total eBTC debt amount withdrawn or repaid for the specified Cdp
    /// @param _isDebtIncrease The flag (true or false) to indicate whether this is a eBTC token withdrawal (debt increase) or a repayment (debt reduce)
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _collBalanceIncrease The total stETH collateral amount deposited (added) for the specified Cdp
    /// @param _useWstETHForDecrease Indicator whether withdrawn collateral is original(stETH) or wrapped version(WstETH)
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function adjustCdp(
        bytes32 _cdpId,
        uint256 _collBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _collBalanceIncrease,
        bool _useWstETHForDecrease,
        PositionManagerPermit calldata _positionManagerPermit
    ) external {
        if (_collBalanceIncrease > 0) {
            uint256 _collVal = _transferInitialStETHFromCaller(_collBalanceIncrease);
            emit ZapOperationEthVariant(
                _cdpId, 
                EthVariantZapOperationType.AdjustCdp, 
                true, 
                address(stEth), 
                _collBalanceIncrease, 
                _collVal,
                msg.sender
            );
        }
        _adjustCdpWithPermit(
            _cdpId,
            _collBalanceDecrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _collBalanceIncrease,
            _useWstETHForDecrease,
            _positionManagerPermit
        );
    }

    /// @dev Increase the collateral for given CDP with raw native Ether
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _ethBalanceIncrease The total stETH collateral (converted from raw Ether) amount deposited (added) for the specified Cdp
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function addCollWithEth(
        bytes32 _cdpId,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _ethBalanceIncrease,
        PositionManagerPermit calldata _positionManagerPermit
    ) external payable {        
        _adjustCdpWithEth(
            _cdpId,
            0,
            0,
            false,
            _upperHint,
            _lowerHint,
            _ethBalanceIncrease,
            false,
            _positionManagerPermit
        );
    }

    /// @notice Transfer an arbitrary token back to you
    function sweepToken(address token, uint256 amount) public {
        require(owner == msg.sender, "Must be owner");

        if (amount > 0) {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    function _openCdpWithPermit(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        PositionManagerPermit calldata _positionManagerPermit
    ) internal returns (bytes32 cdpId) {
        // Check token balances of Zap before operation
        require(
            stEth.balanceOf(address(this)) >= _stEthBalance,
            "EbtcZapRouter: not enough collateral for open!"
        );

        _requireZeroOrMinAdjustment(_debt);
        _requireAtLeastMinNetStEthBalance(_stEthBalance - LIQUIDATOR_REWARD);

        _permitPositionManagerApproval(borrowerOperations, _positionManagerPermit);

        cdpId = borrowerOperations.openCdpFor(
            _debt,
            _upperHint,
            _lowerHint,
            _stEthBalance,
            msg.sender
        );

        ebtc.transfer(msg.sender, _debt);

        // Token balances should not have changed after operation
        // Created CDP should be owned by borrower
    }

    function _closeCdpWithPermit(
        bytes32 _cdpId,
        bool _useWstETH,
        PositionManagerPermit calldata _positionManagerPermit
    ) internal {
        require(msg.sender == _getOwnerAddress(_cdpId), "EbtcZapRouter: not owner for close!");

        // for debt repayment
        uint256 _debt = ICdpManagerData(address(cdpManager)).getSyncedCdpDebt(_cdpId);
        ebtc.transferFrom(msg.sender, address(this), _debt);

        _permitPositionManagerApproval(borrowerOperations, _positionManagerPermit);

        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        borrowerOperations.closeCdp(_cdpId);
        uint256 _zapStEthBalanceAfter = stEth.balanceOf(address(this));
        uint256 _stETHDiff = _zapStEthBalanceAfter - _zapStEthBalanceBefore;

        _transferStEthToCaller(_cdpId, EthVariantZapOperationType.CloseCdp, _useWstETH, _stETHDiff);
    }

    function _adjustCdpWithPermit(
        bytes32 _cdpId,
        uint256 _collBalanceDecrease,
        uint256 _debtChange,
        bool isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _collBalanceIncrease,
        bool _useWstETH,
        PositionManagerPermit calldata _positionManagerPermit
    ) internal {
        require(msg.sender == _getOwnerAddress(_cdpId), "EbtcZapRouter: not owner for adjust!");
        require(
            (_collBalanceDecrease > 0 && _collBalanceIncrease == 0) ||
                (_collBalanceIncrease > 0 && _collBalanceDecrease == 0) ||
                (_collBalanceIncrease == 0 && _collBalanceDecrease == 0),
            "EbtcZapRouter: can't add and remove collateral at the same time!"
        );

        _requireNonZeroAdjustment(_collBalanceIncrease, _collBalanceDecrease, _debtChange);
        _requireZeroOrMinAdjustment(_debtChange);
        _requireZeroOrMinAdjustment(_collBalanceIncrease);
        _requireZeroOrMinAdjustment(_collBalanceDecrease);

        _permitPositionManagerApproval(borrowerOperations, _positionManagerPermit);

        // for debt decrease
        if (!isDebtIncrease && _debtChange > 0) {
            ebtc.transferFrom(msg.sender, address(this), _debtChange);
        }

        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        borrowerOperations.adjustCdpWithColl(
            _cdpId,
            _collBalanceDecrease,
            _debtChange,
            isDebtIncrease,
            _upperHint,
            _lowerHint,
            _collBalanceIncrease
        );
        uint256 _zapStEthBalanceAfter = stEth.balanceOf(address(this));

        // Send any withdrawn debt back to borrower
        if (isDebtIncrease && _debtChange > 0) {
            ebtc.transfer(msg.sender, _debtChange);
        }

        // Send any withdrawn collateral to back to borrower
        if (_collBalanceDecrease > 0) {
            _transferStEthToCaller(
                _cdpId,
                EthVariantZapOperationType.AdjustCdp,
                _useWstETH,
                _zapStEthBalanceAfter - _zapStEthBalanceBefore
            );
        }
    }

    function _requireNonZeroAdjustment(
        uint256 _stEthBalanceIncrease,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange
    ) internal pure {
        require(
            _stEthBalanceIncrease > 0 || _stEthBalanceDecrease > 0 || _debtChange > 0,
            "EbtcZapRouter: There must be either a collateral or debt change"
        );
    }
}
