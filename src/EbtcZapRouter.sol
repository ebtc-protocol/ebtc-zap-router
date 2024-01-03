// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, console2} from "forge-std/Test.sol";
import {IERC3156FlashLender} from "@ebtc/contracts/Interfaces/IERC3156FlashLender.sol";
import {ZapRouterBase} from "./ZapRouterBase.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManagerData.sol";
import {ICdpManager} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IBorrowerOperations} from "@ebtc/contracts/Interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/Interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {SafeERC20} from "@ebtc/contracts/Dependencies/SafeERC20.sol";
import {IStETH} from "./interface/IStETH.sol";
import {IWrappedETH} from "./interface/IWrappedETH.sol";
import {IEbtcZapRouter} from "./interface/IEbtcZapRouter.sol";
import {IWstETH} from "./interface/IWstETH.sol";

contract EbtcZapRouter is ZapRouterBase, IEbtcZapRouter {
    using SafeERC20 for IERC20;

    address public constant NATIVE_ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IERC20 public immutable wrappedEth;
    IERC20 public immutable wstEth;

    constructor(DeploymentParams memory params) ZapRouterBase(params) {
        wrappedEth = IERC20(params.weth);
        wstEth = IERC20(params.wstEth);

        wstEth.approve(address(wstEth), type(uint256).max);
    }

    function temp_openCdpWithLeverage(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance, // margin balance
        PositionManagerPermit memory _positionManagerPermit,
        bytes calldata _exchangeData
    ) external returns (bytes32 cdpId) {
        // TODO: calculate this for real, need to figure out how to specify leverage ratio
        // TODO: check max leverage here once we know how leverage will be specified
        uint256 flAmount = _debtToCollateral(_debt);

        // We need to deposit slightly less collateral to account for fees / slippage
        // COLLATERAL_BUFFER is a temporary solution to make the tests pass
        // TODO: discuss this and see if it's better to pass in some sort of slippage setting
        uint256 totalCollateral = ((flAmount + _stEthBalance) * COLLATERAL_BUFFER) /
            SLIPPAGE_PRECISION;

        _permitPositionManagerApproval(_positionManagerPermit);

        cdpId = sortedCdps.toCdpId(msg.sender, block.number, sortedCdps.nextCdpNonce());

        OpenCdpForOperation memory cdp;

        cdp.eBTCToMint = _debt;
        cdp._upperHint = _upperHint;
        cdp._lowerHint = _lowerHint;
        cdp.stETHToDeposit = totalCollateral;
        cdp.borrower = msg.sender;

        _openCdpOperation({
            _cdpId: cdpId,
            _cdp: cdp,
            _flAmount: flAmount,
            _stEthBalance: _stEthBalance,
            _exchangeData: _exchangeData
        });

        // TODO: emit event
        // TODO: return cdpId, otherwise useful data? check with UI devs
    }

    function temp_closeCdpWithLeverage(
        bytes32 _cdpId,
        PositionManagerPermit memory _positionManagerPermit,
        uint256 maxSlippage,
        bytes calldata _exchangeData
    ) external {
        ICdpManagerData.Cdp memory cdpInfo = cdpManager.Cdps(_cdpId);

        uint256 flashFee = IERC3156FlashLender(address(borrowerOperations)).flashFee(
            address(ebtcToken),
            cdpInfo.debt
        );

        _permitPositionManagerApproval(_positionManagerPermit);

        _closeCdpOperation({
            _cdpId: _cdpId,
            _debt: cdpInfo.debt,
            _flashFee: flashFee,
            _maxSlippage: maxSlippage,
            _exchangeData: _exchangeData
        });
    }

        // TODO: emit event
        // TODO: otherwise useful data? check with UI devs
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
        PositionManagerPermit memory _positionManagerPermit
    ) external returns (bytes32 cdpId) {
        uint256 _collVal = _transferInitialStETHFromCaller(_stEthBalance);

        require(
            _stEthBalance == _collVal,
            "EbtcZapRouter: stETH conversion error"
        );

        cdpId = _openCdpWithPermit(
            _debt,
            _upperHint,
            _lowerHint,
            _collVal,
            _positionManagerPermit
        );

        emit ZapOperationEthVariant(cdpId, EthVariantZapOperationType.OpenCdp, true, address(stETH), _stEthBalance, _collVal);
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
        PositionManagerPermit memory _positionManagerPermit
    ) external payable returns (bytes32 cdpId) {
        uint256 _collVal = _convertRawEthToStETH(_ethBalance);

        cdpId = _openCdpWithPermit(
            _debt,
            _upperHint,
            _lowerHint,
            _collVal,
            _positionManagerPermit
        );

        emit ZapOperationEthVariant(cdpId, EthVariantZapOperationType.OpenCdp, true, NATIVE_ETH_ADDRESS, _ethBalance, _collVal);
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
        PositionManagerPermit memory _positionManagerPermit
    ) external returns (bytes32 cdpId) {
        uint256 _collVal = _convertWrappedEthToStETH(_wethBalance);

        cdpId = _openCdpWithPermit(
            _debt,
            _upperHint,
            _lowerHint,
            _collVal,
            _positionManagerPermit
        );
        
        emit ZapOperationEthVariant(cdpId, EthVariantZapOperationType.OpenCdp, true, address(wrappedEth), _wethBalance, _collVal);
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
        PositionManagerPermit memory _positionManagerPermit
    ) external returns (bytes32 cdpId) {
        uint256 _collVal = _convertWstEthToStETH(_wstEthBalance);

        cdpId = _openCdpWithPermit(
            _debt,
            _upperHint,
            _lowerHint,
            _collVal,
            _positionManagerPermit
        );

        emit ZapOperationEthVariant(cdpId, EthVariantZapOperationType.OpenCdp, true, address(wstEth), _wstEthBalance, _collVal);
    }

    /// @dev Close a CDP with original collateral(stETH) returned to CDP owner
    /// @dev Note plain collateral(stETH) is returned no matter whatever asset is zapped in
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function closeCdp(
        bytes32 _cdpId,
        PositionManagerPermit memory _positionManagerPermit
    ) external {
        _closeCdpWithPermit(_cdpId, false, _positionManagerPermit);
    }

    /// @dev Close a CDP with wrapped version of collateral(WstETH) returned to CDP owner
    /// @dev Note plain collateral(stETH) is returned no matter whatever asset is zapped in
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function closeCdpForWstETH(
        bytes32 _cdpId,
        PositionManagerPermit memory _positionManagerPermit
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
        PositionManagerPermit memory _positionManagerPermit
    ) external payable {
        uint256 _collBalanceIncrease = _ethBalanceIncrease;
        if (_ethBalanceIncrease > 0) {
            _collBalanceIncrease = _convertRawEthToStETH(_ethBalanceIncrease);
            emit ZapOperationEthVariant(_cdpId, EthVariantZapOperationType.AdjustCdp, true, NATIVE_ETH_ADDRESS, _ethBalanceIncrease, _collBalanceIncrease);
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
        PositionManagerPermit memory _positionManagerPermit
    ) external {
        uint256 _collBalanceIncrease = _wethBalanceIncrease;
        if (_wethBalanceIncrease > 0) {
            _collBalanceIncrease = _convertWrappedEthToStETH(
                _wethBalanceIncrease
            );
            emit ZapOperationEthVariant(_cdpId, EthVariantZapOperationType.AdjustCdp, true, address(wrappedEth), _wethBalanceIncrease, _collBalanceIncrease);
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
        PositionManagerPermit memory _positionManagerPermit
    ) external {
        uint256 _collBalanceIncrease = _wstEthBalanceIncrease;

        // wstETH In
        if (_wstEthBalanceIncrease > 0) {
            _collBalanceIncrease = _convertWstEthToStETH(
                _wstEthBalanceIncrease
            );
            emit ZapOperationEthVariant(_cdpId, EthVariantZapOperationType.AdjustCdp, false, address(wstEth), _wstEthBalanceIncrease, _collBalanceIncrease);
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
        PositionManagerPermit memory _positionManagerPermit
    ) external {
        if (_collBalanceIncrease > 0) {
         emit ZapOperationEthVariant(_cdpId, EthVariantZapOperationType.AdjustCdp, false, address(stETH), _collBalanceIncrease, _collBalanceIncrease);
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
        PositionManagerPermit memory _positionManagerPermit
    ) external payable {
        uint256 _stEthToAdd = _convertRawEthToStETH(_ethBalanceIncrease);

        _adjustCdpWithPermit(
            _cdpId,
            0,
            0,
            false,
            _upperHint,
            _lowerHint,
            _stEthToAdd,
            false,
            _positionManagerPermit
        );
    }

    function _openCdpWithPermit(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) internal returns (bytes32 cdpId) {
        // Check token balances of Zap before operation
        require(
            stETH.balanceOf(address(this)) >= _stEthBalance,
            "EbtcZapRouter: not enough collateral for open!"
        );

        _permitPositionManagerApproval(_positionManagerPermit);

        cdpId = borrowerOperations.openCdpFor(
            _debt,
            _upperHint,
            _lowerHint,
            _stEthBalance,
            msg.sender
        );

        ebtcToken.transfer(msg.sender, _debt);

        // Token balances should not have changed after operation
        // Created CDP should be owned by borrower
    }

    function _closeCdpWithPermit(
        bytes32 _cdpId,
        bool _useWstETH,
        PositionManagerPermit memory _positionManagerPermit
    ) internal {
        require(
            msg.sender == _getOwnerAddress(_cdpId),
            "EbtcZapRouter: not owner for close!"
        );

        // for debt repayment
        uint256 _debt = ICdpManagerData(address(cdpManager)).getSyncedCdpDebt(
            _cdpId
        );
        ebtcToken.transferFrom(msg.sender, address(this), _debt);

        _permitPositionManagerApproval(_positionManagerPermit);

        uint256 _zapStEthBalanceBefore = stETH.balanceOf(address(this));
        borrowerOperations.closeCdp(_cdpId);
        uint256 _zapStEthBalanceAfter = stETH.balanceOf(address(this));
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
            emit ZapOperationEthVariant(_cdpId, _operationType, false, address(wstEth), _wstETHVal, _stEthVal);

            wstEth.transfer(msg.sender, _wstETHVal);
        } else {
            // return original collateral(stETH)
            emit ZapOperationEthVariant(_cdpId, _operationType, false, address(stETH), _stEthVal, _stEthVal);
            stETH.transfer(msg.sender, _stEthVal);
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
        PositionManagerPermit memory _positionManagerPermit
    ) internal {
        require(
            msg.sender == _getOwnerAddress(_cdpId),
            "EbtcZapRouter: not owner for adjust!"
        );
        require(
            (_collBalanceDecrease > 0 && _collBalanceIncrease == 0) ||
                (_collBalanceIncrease > 0 && _collBalanceDecrease == 0),
            "EbtcZapRouter: can't add and remove collateral at the same time!"
        );

        _permitPositionManagerApproval(_positionManagerPermit);

        // for debt decrease
        if (!isDebtIncrease && _debtChange > 0) {
            ebtcToken.transferFrom(msg.sender, address(this), _debtChange);
        }

        uint256 _zapStEthBalanceBefore = stETH.balanceOf(address(this));
        borrowerOperations.adjustCdpWithColl(
            _cdpId,
            _collBalanceDecrease,
            _debtChange,
            isDebtIncrease,
            _upperHint,
            _lowerHint,
            _collBalanceIncrease
        );
        uint256 _zapStEthBalanceAfter = stETH.balanceOf(address(this));

        // Send any withdrawn debt back to borrower
        if (isDebtIncrease && _debtChange > 0) {
            ebtcToken.transfer(msg.sender, _debtChange);
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
        uint256 _balBefore = stETH.balanceOf(address(this));
        stETH.transferFrom(msg.sender, address(this), _initialStETH);
        uint256 _deposit = stETH.balanceOf(address(this)) - _balBefore;
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
        uint256 _balBefore = stETH.balanceOf(address(this));
        // TODO call submit() with a referral?
        payable(address(stETH)).call{value: _initialETH}("");
        uint256 _deposit = stETH.balanceOf(address(this)) - _balBefore;
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

        uint256 _stETHBalBefore = stETH.balanceOf(address(this));
        IWstETH(address(wstEth)).unwrap(_initialWstETH);
        uint256 _stETHReiceived = stETH.balanceOf(address(this)) -
            _stETHBalBefore;

        return _stETHReiceived;
    }

    function _getOwnerAddress(bytes32 cdpId) internal pure returns (address) {
        uint256 _tmp = uint256(cdpId) >> 96;
        return address(uint160(_tmp));
    }
}
