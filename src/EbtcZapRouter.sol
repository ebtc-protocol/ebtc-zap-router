// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ICdpManagerData} from "@ebtc/contracts/interfaces/ICdpManagerData.sol";
import {ICdpManager} from "@ebtc/contracts/interfaces/ICdpManager.sol";
import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {SafeERC20} from "@ebtc/contracts/Dependencies/SafeERC20.sol";
import {IStETH} from "./interface/IStETH.sol";
import {IWrappedETH} from "./interface/IWrappedETH.sol";
import {IEbtcZapRouter} from "./interface/IEbtcZapRouter.sol";
import {IWstETH} from "./interface/IWstETH.sol";

interface IMinChangeGetter {
    function MIN_CHANGE() external view returns (uint256);
}

contract EbtcZapRouter is IEbtcZapRouter {
    using SafeERC20 for IERC20;

    address public constant NATIVE_ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public constant LIQUIDATOR_REWARD = 2e17;
    uint256 public constant MIN_NET_STETH_BALANCE = 2e18;

    IStETH public immutable stEth;
    IERC20 public immutable ebtc;
    IERC20 public immutable wrappedEth;
    IERC20 public immutable wstEth;
    IBorrowerOperations public immutable borrowerOperations;
    ICdpManager public immutable cdpManager;
    address public immutable owner;
    uint256 public immutable MIN_CHANGE;

    constructor(
        IERC20 _wstEth,
        IERC20 _wEth,
        IStETH _stEth,
        IERC20 _ebtc,
        IBorrowerOperations _borrowerOperations,
        ICdpManager _cdpManager,
        address _owner
    ) {
        wstEth = _wstEth;
        wrappedEth = _wEth;
        stEth = _stEth;
        ebtc = _ebtc;
        borrowerOperations = _borrowerOperations;
        cdpManager = _cdpManager;
        owner = _owner;

        // Infinite Approvals @TODO: do these stay at max for each token?
        stEth.approve(address(borrowerOperations), type(uint256).max);
        wrappedEth.approve(address(wrappedEth), type(uint256).max);
        wstEth.approve(address(wstEth), type(uint256).max);
        stEth.approve(address(wstEth), type(uint256).max);

        MIN_CHANGE = IMinChangeGetter(address(borrowerOperations)).MIN_CHANGE();
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
            _collBalanceIncrease = _convertWrappedEthToStETH(
                _wethBalanceIncrease
            );
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
            _collBalanceIncrease = _convertWstEthToStETH(
                _wstEthBalanceIncrease
            );
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

        _permitPositionManagerApproval(_positionManagerPermit);

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
        require(
            msg.sender == _getOwnerAddress(_cdpId),
            "EbtcZapRouter: not owner for close!"
        );

        // for debt repayment
        uint256 _debt = ICdpManagerData(address(cdpManager)).getSyncedCdpDebt(
            _cdpId
        );
        ebtc.transferFrom(msg.sender, address(this), _debt);

        _permitPositionManagerApproval(_positionManagerPermit);

        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        borrowerOperations.closeCdp(_cdpId);
        uint256 _zapStEthBalanceAfter = stEth.balanceOf(address(this));
        uint256 _stETHDiff = _zapStEthBalanceAfter - _zapStEthBalanceBefore;

        _transferStEthToCaller(_cdpId, EthVariantZapOperationType.CloseCdp, _useWstETH, _stETHDiff);
    }

    function _transferStEthToCaller(
        bytes32 _cdpId,
        EthVariantZapOperationType _operationType,
        bool _useWstETH,
        uint256 _stEthVal
    ) internal {
        if (_useWstETH) {
            // return wrapped version(WstETH)
            uint256 _wstETHVal = IWstETH(address(wstEth)).wrap(_stEthVal);
            emit ZapOperationEthVariant(
                _cdpId, 
                _operationType, 
                false, 
                address(wstEth), 
                _wstETHVal, 
                _stEthVal,
                msg.sender
            );

            wstEth.transfer(msg.sender, _wstETHVal);
        } else {
            // return original collateral(stETH)
            emit ZapOperationEthVariant(
                _cdpId, 
                _operationType, 
                false, 
                address(stEth), 
                _stEthVal, 
                _stEthVal,
                msg.sender
            );
            stEth.transfer(msg.sender, _stEthVal);
        }
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
        require(
            msg.sender == _getOwnerAddress(_cdpId),
            "EbtcZapRouter: not owner for adjust!"
        );
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

        _permitPositionManagerApproval(_positionManagerPermit);

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

    function _transferInitialStETHFromCaller(
        uint256 _initialStETH
    ) internal returns (uint256) {
        // check before-after balances for 1-wei corner case
        uint256 _balBefore = stEth.balanceOf(address(this));
        stEth.transferFrom(msg.sender, address(this), _initialStETH);
        uint256 _deposit = stEth.balanceOf(address(this)) - _balBefore;
        return _deposit;
    }

    function _convertRawEthToStETH(
        uint256 _initialETH
    ) internal returns (uint256) {
        require(
            msg.value == _initialETH,
            "EbtcZapRouter: Incorrect ETH amount"
        );
        return _depositRawEthIntoLido(_initialETH);
    }

    function _depositRawEthIntoLido(
        uint256 _initialETH
    ) internal returns (uint256) {
        // check before-after balances for 1-wei corner case
        uint256 _balBefore = stEth.balanceOf(address(this));
        // TODO call submit() with a referral?
        payable(address(stEth)).call{value: _initialETH}("");
        uint256 _deposit = stEth.balanceOf(address(this)) - _balBefore;
        return _deposit;
    }

    function _convertWrappedEthToStETH(
        uint256 _initialWETH
    ) internal returns (uint256) {
        uint256 _wETHBalBefore = wrappedEth.balanceOf(address(this));
        wrappedEth.transferFrom(msg.sender, address(this), _initialWETH);
        uint256 _wETHReiceived = wrappedEth.balanceOf(address(this)) -
            _wETHBalBefore;

        uint256 _rawETHBalBefore = address(this).balance;
        IWrappedETH(address(wrappedEth)).withdraw(_wETHReiceived);
        uint256 _rawETHConverted = address(this).balance - _rawETHBalBefore;
        return _depositRawEthIntoLido(_rawETHConverted);
    }

    function _convertWstEthToStETH(
        uint256 _initialWstETH
    ) internal returns (uint256) {
        require(
            wstEth.transferFrom(msg.sender, address(this), _initialWstETH),
            "EbtcZapRouter: transfer wstETH failure!"
        );

        uint256 _stETHBalBefore = stEth.balanceOf(address(this));
        IWstETH(address(wstEth)).unwrap(_initialWstETH);
        uint256 _stETHReiceived = stEth.balanceOf(address(this)) -
            _stETHBalBefore;

        return _stETHReiceived;
    }

    function _permitPositionManagerApproval(
        PositionManagerPermit calldata _positionManagerPermit
    ) internal {
        try
            borrowerOperations.permitPositionManagerApproval(
                msg.sender,
                address(this),
                IPositionManagers.PositionManagerApproval.OneTime,
                _positionManagerPermit.deadline,
                _positionManagerPermit.v,
                _positionManagerPermit.r,
                _positionManagerPermit.s
            )
        {} catch {
            /// @notice adding try...catch around to mitigate potential permit front-running
            /// see: https://www.trust-security.xyz/post/permission-denied
        }
    }

    function _getOwnerAddress(bytes32 cdpId) internal pure returns (address) {
        uint256 _tmp = uint256(cdpId) >> 96;
        return address(uint160(_tmp));
    }

    function _requireZeroOrMinAdjustment(uint256 _change) internal view {
        require(
            _change == 0 || _change >= MIN_CHANGE,
            "EbtcZapRouter: Debt or collateral change must be zero or above min"
        );
    }

    function _requireAtLeastMinNetStEthBalance(uint256 _stEthBalance) internal pure {
        require(
            _stEthBalance >= MIN_NET_STETH_BALANCE,
            "EbtcZapRouter: Cdp's net stEth balance must not fall below minimum"
        );
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
