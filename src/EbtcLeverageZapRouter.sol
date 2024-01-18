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

interface IMinChangeGetter {
    function MIN_CHANGE() external view returns (uint256);
}

contract EbtcLeverageZapRouter is LeverageZapRouterBase, IEbtcLeverageZapRouter {
    using SafeERC20 for IERC20;

    uint256 public immutable MIN_CHANGE;

    constructor(
        IEbtcLeverageZapRouter.DeploymentParams memory params
    ) LeverageZapRouterBase(params) {
        MIN_CHANGE = IMinChangeGetter(params.borrowerOperations).MIN_CHANGE();
    }

    function openCdpWithEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _ethMarginBalance,
        uint256 _stEthDepositAmount,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
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
            _exchangeData
        );

        emit ZapOperationEthVariant(
            cdpId,
            EthVariantZapOperationType.OpenCdp,
            true,
            NATIVE_ETH_ADDRESS,
            _ethMarginBalance,
            _collVal
        );
    }

    function openCdpWithWstEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _wstEthMarginBalance,
        uint256 _stEthDepositAmount,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
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
            _exchangeData
        );

        emit ZapOperationEthVariant(
            cdpId,
            EthVariantZapOperationType.OpenCdp,
            true,
            address(wstEth),
            _wstEthMarginBalance,
            _collVal
        );
    }

    function openCdpWithWrappedEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _wethMarginBalance,
        uint256 _stEthDepositAmount,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
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
            _exchangeData
        );

        emit ZapOperationEthVariant(
            cdpId,
            EthVariantZapOperationType.OpenCdp,
            true,
            address(wrappedEth),
            _wethMarginBalance,
            _collVal
        );
    }

    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _stEthMarginAmount,
        uint256 _stEthDepositAmount,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) external returns (bytes32 cdpId) {
        uint256 _collVal = _transferInitialStETHFromCaller(_stEthMarginAmount);

        cdpId = _openCdp(
            _debt,
            _upperHint,
            _lowerHint,
            _stEthLoanAmount,
            0, // _stEthMarginAmount transferred above
            _stEthDepositAmount,
            _positionManagerPermit,
            _exchangeData
        );

        emit ZapOperationEthVariant(
            cdpId,
            EthVariantZapOperationType.OpenCdp,
            true,
            address(stEth),
            _stEthMarginAmount,
            _collVal
        );
    }

    function _openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _stEthMarginAmount,
        uint256 _stEthDepositAmount,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) internal nonReentrant returns (bytes32 cdpId) {
        _permitPositionManagerApproval(_positionManagerPermit);

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
            _stEthBalance: _stEthMarginAmount,
            _exchangeData: _exchangeData
        });
    }

    function closeCdp(
        bytes32 _cdpId,
        PositionManagerPermit calldata _positionManagerPermit,
        uint256 _stEthAmount,
        bytes calldata _exchangeData
    ) external {
        _closeCdp(_cdpId, _positionManagerPermit, _stEthAmount, false, _exchangeData);
    }

    function closeCdpForWstETH(
        bytes32 _cdpId,
        PositionManagerPermit calldata _positionManagerPermit,
        uint256 _stEthAmount,
        bytes calldata _exchangeData
    ) external {
        _closeCdp(_cdpId, _positionManagerPermit, _stEthAmount, true, _exchangeData);
    }

    function _closeCdp(
        bytes32 _cdpId,
        PositionManagerPermit calldata _positionManagerPermit,
        uint256 _stEthAmount,
        bool _useWstETH,
        bytes calldata _exchangeData
    ) internal nonReentrant {
        ICdpManagerData.Cdp memory cdpInfo = cdpManager.Cdps(_cdpId);

        _permitPositionManagerApproval(_positionManagerPermit);

        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        _closeCdpOperation({
            _cdpId: _cdpId,
            _debt: cdpInfo.debt,
            _stEthAmount: _stEthAmount,
            _exchangeData: _exchangeData
        });
        uint256 _zapStEthBalanceAfter = stEth.balanceOf(address(this));
        uint256 _stETHDiff = _zapStEthBalanceAfter - _zapStEthBalanceBefore;

        _transferStEthToCaller(_cdpId, EthVariantZapOperationType.CloseCdp, _useWstETH, _stETHDiff);
    }

    function _requireMinAdjustment(uint256 _change) internal view {
        require(
            _change >= MIN_CHANGE,
            "EbtcLeverageZapRouter: Debt or collateral change must be above min"
        );
    }

    function _requireZeroOrMinAdjustment(uint256 _change) internal view {
        require(
            _change == 0 || _change >= MIN_CHANGE,
            "EbtcLeverageZapRouter: Margin increase must be zero or above min"
        );
    }

    function adjustCdpWithEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) external {
        if (params._isStEthMarginIncrease && params._stEthMarginBalance > 0) {
            params._stEthMarginBalance = _convertRawEthToStETH(params._stEthMarginBalance);
        }
        _adjustCdp(_cdpId, params, _positionManagerPermit, _exchangeData);
    }

    function adjustCdpWithWstEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) external {
        if (params._isStEthMarginIncrease && params._stEthMarginBalance > 0) {
            params._stEthMarginBalance = _convertWstEthToStETH(params._stEthMarginBalance);
        }
        _adjustCdp(_cdpId, params, _positionManagerPermit, _exchangeData);
    }

    function openCdpWithWrappedEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) external {
        if (params._isStEthMarginIncrease && params._stEthMarginBalance > 0) {
            params._stEthMarginBalance = _convertWrappedEthToStETH(params._stEthMarginBalance);
        }
        _adjustCdp(_cdpId, params, _positionManagerPermit, _exchangeData);
    }

    function adjustCdp(
        bytes32 _cdpId,
        AdjustCdpParams calldata params,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) external {
        _adjustCdp(_cdpId, params, _positionManagerPermit, _exchangeData);
    }

    function _adjustCdp(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) internal nonReentrant {
        _requireMinAdjustment(params._debtChange);
        _requireMinAdjustment(params._stEthBalanceChange);
        _requireZeroOrMinAdjustment(params._stEthMarginBalance);

        (uint256 debt, ) = ICdpManager(address(cdpManager)).getSyncedDebtAndCollShares(_cdpId);

        _permitPositionManagerApproval(_positionManagerPermit);

        uint256 marginDecrease = params._isStEthBalanceIncrease ? 0 : params._stEthBalanceChange;
        if (!params._isStEthMarginIncrease && params._stEthMarginBalance > 0) {
            marginDecrease += params._stEthMarginBalance;
        }

        uint256 marginIncrease = params._isStEthBalanceIncrease ? params._stEthBalanceChange : 0;
        if (params._isStEthMarginIncrease && params._stEthMarginBalance > 0) {
            marginIncrease += params._stEthMarginBalance;
        }

        uint256 _zapStEthBalanceBefore = stEth.balanceOf(address(this));
        _adjustCdpOperation({
            _cdpId: _cdpId,
            _flType: params._isDebtIncrease ? FlashLoanType.stETH : FlashLoanType.eBTC,
            _flAmount: params._flashLoanAmount,
            _marginIncrease: params._isStEthMarginIncrease ? params._stEthMarginBalance : 0,
            _cdp: AdjustCdpOperation({
                _cdpId: _cdpId,
                _EBTCChange: params._debtChange,
                _isDebtIncrease: params._isDebtIncrease,
                _upperHint: params._upperHint,
                _lowerHint: params._lowerHint,
                _stEthBalanceIncrease: marginIncrease,
                _stEthBalanceDecrease: marginDecrease
            }),
            newDebt: params._isDebtIncrease ? debt + params._debtChange : debt - params._debtChange,
            newColl: 0,
            _exchangeData: _exchangeData
        });
        uint256 _zapStEthBalanceDiff = stEth.balanceOf(address(this)) - _zapStEthBalanceBefore;

        if (_zapStEthBalanceDiff > 0) {
            _transferStEthToCaller(
                _cdpId,
                EthVariantZapOperationType.AdjustCdp,
                params._useWstETHForDecrease,
                _zapStEthBalanceDiff
            );
        }
    }
}
