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

        if (_positionManagerPermit.length > 0) {
            PositionManagerPermit memory approval = abi.decode(_positionManagerPermit, (PositionManagerPermit));
            _permitPositionManagerApproval(borrowerOperations, approval);
        }

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
            // collateral already transferred in by the caller
            _stEthBalance: 0,
            _tradeData: _tradeData
        });

        if (_positionManagerPermit.length > 0) {
            borrowerOperations.renouncePositionManagerApproval(msg.sender);
        }
    }

    function closeCdp(
        bytes32 _cdpId,
        bytes calldata _positionManagerPermit,
        uint256 _stEthAmount,
        TradeData calldata _tradeData
    ) external {
        _closeCdp(_cdpId, _positionManagerPermit, _stEthAmount, false, _tradeData);
    }

    function closeCdpForWstETH(
        bytes32 _cdpId,
        bytes calldata _positionManagerPermit,
        uint256 _stEthAmount,
        TradeData calldata _tradeData
    ) external {
        _closeCdp(_cdpId, _positionManagerPermit, _stEthAmount, true, _tradeData);
    }

    function _closeCdp(
        bytes32 _cdpId,
        bytes calldata _positionManagerPermit,
        uint256 _stEthAmount,
        bool _useWstETH,
        TradeData calldata _tradeData
    ) internal nonReentrant {
        require(msg.sender == _getOwnerAddress(_cdpId), "EbtcLeverageZapRouter: not owner for close!");

        uint256 debt = ICdpManager(address(cdpManager)).getSyncedCdpDebt(_cdpId);

        if (_positionManagerPermit.length > 0) {
            PositionManagerPermit memory approval = abi.decode(_positionManagerPermit, (PositionManagerPermit));
            _permitPositionManagerApproval(borrowerOperations, approval);
        }

        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        _closeCdpOperation({
            _cdpId: _cdpId,
            _debt: debt,
            _stEthAmount: _stEthAmount,
            _tradeData: _tradeData
        });
        uint256 _zapStEthBalanceAfter = stEth.balanceOf(address(this));
        uint256 _stETHDiff = _zapStEthBalanceAfter - _zapStEthBalanceBefore;

        if (_positionManagerPermit.length > 0) {
            borrowerOperations.renouncePositionManagerApproval(msg.sender);
        }

        _transferStEthToCaller(_cdpId, EthVariantZapOperationType.CloseCdp, _useWstETH, _stETHDiff);
    }

    function _requireMinAdjustment(uint256 _change) internal view {
        require(
            _change >= MIN_CHANGE,
            "EbtcLeverageZapRouter: Debt or collateral change must be above min"
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

    function adjustCdpWithEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external payable {
        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        if (params.isStEthMarginIncrease && params.stEthMarginBalance > 0) {
            params.stEthMarginBalance = _convertRawEthToStETH(params.stEthMarginBalance);
        }
        _adjustCdp(_cdpId, params, _positionManagerPermit, _tradeData, _zapStEthBalanceBefore);
    }

    function adjustCdpWithWstEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external {
        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        if (params.isStEthMarginIncrease && params.stEthMarginBalance > 0) {
            params.stEthMarginBalance = _convertWstEthToStETH(params.stEthMarginBalance);
        }
        _adjustCdp(_cdpId, params, _positionManagerPermit, _tradeData, _zapStEthBalanceBefore);
    }

    function adjustCdpWithWrappedEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external {
        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        if (params.isStEthMarginIncrease && params.stEthMarginBalance > 0) {
            params.stEthMarginBalance = _convertWrappedEthToStETH(params.stEthMarginBalance);
        }
        _adjustCdp(_cdpId, params, _positionManagerPermit, _tradeData, _zapStEthBalanceBefore);
    }

    function adjustCdp(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external {
        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        if (params.isStEthMarginIncrease && params.stEthMarginBalance > 0) {
            params.stEthMarginBalance = _transferInitialStETHFromCaller(params.stEthMarginBalance);
        }
        _adjustCdp(_cdpId, params, _positionManagerPermit, _tradeData, _zapStEthBalanceBefore);
    }

    function _adjustCdp(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData,
        uint256 _zapStEthBalanceBefore
    ) internal nonReentrant {
        require(msg.sender == _getOwnerAddress(_cdpId), "EbtcLeverageZapRouter: not owner for adjust!");
        _requireMinAdjustment(params.debtChange);
        _requireMinAdjustment(params.stEthBalanceChange);
        _requireZeroOrMinAdjustment(params.stEthMarginBalance);

        (uint256 debt, ) = ICdpManager(address(cdpManager)).getSyncedDebtAndCollShares(_cdpId);

        if (_positionManagerPermit.length > 0) {
            PositionManagerPermit memory approval = abi.decode(_positionManagerPermit, (PositionManagerPermit));
            _permitPositionManagerApproval(borrowerOperations, approval);
        }
        
        uint256 marginDecrease = params.isStEthBalanceIncrease ? 0 : params.stEthBalanceChange;
        if (!params.isStEthMarginIncrease && params.stEthMarginBalance > 0) {
            marginDecrease += params.stEthMarginBalance;
        }

        uint256 marginIncrease = params.isStEthBalanceIncrease ? params.stEthBalanceChange : 0;
        if (params.isStEthMarginIncrease && params.stEthMarginBalance > 0) {
            marginIncrease += params.stEthMarginBalance;
        }

        _requireSingularMarginChange(marginIncrease, marginDecrease);

        _adjustCdpOperation({
            _cdpId: _cdpId,
            _flType: params.isDebtIncrease ? FlashLoanType.stETH : FlashLoanType.eBTC,
            _flAmount: params.flashLoanAmount,
            // collateral already transferred in by the caller
            _marginIncrease: 0,
            _cdp: AdjustCdpOperation({
                _cdpId: _cdpId,
                _EBTCChange: params.debtChange,
                _isDebtIncrease: params.isDebtIncrease,
                _upperHint: params.upperHint,
                _lowerHint: params.lowerHint,
                _stEthBalanceIncrease: marginIncrease,
                _stEthBalanceDecrease: marginDecrease
            }),
            newDebt: params.isDebtIncrease ? debt + params.debtChange : debt - params.debtChange,
            newColl: 0,
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
                params.useWstETHForDecrease,
                _zapStEthBalanceDiff
            );
        }
    }
}
