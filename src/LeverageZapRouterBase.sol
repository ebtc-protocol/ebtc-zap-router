// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IPositionManagers} from "@ebtc/contracts/Interfaces/IBorrowerOperations.sol";
import {IPriceFeed} from "@ebtc/contracts/Interfaces/IPriceFeed.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {LeverageMacroBase} from "@ebtc/contracts/LeverageMacroBase.sol";
import {ReentrancyGuard} from "@ebtc/contracts/Dependencies/ReentrancyGuard.sol";
import {SafeERC20} from "@ebtc/contracts/Dependencies/SafeERC20.sol";
import {IEbtcLeverageZapRouter} from "./interface/IEbtcLeverageZapRouter.sol";
import {ZapRouterBase} from "./ZapRouterBase.sol";
import {IStETH} from "./interface/IStETH.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";

abstract contract LeverageZapRouterBase is ZapRouterBase, LeverageMacroBase, ReentrancyGuard, IEbtcLeverageZapRouter {
    using SafeERC20 for IERC20;

    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant BPS = 10000;

    address public immutable theOwner;
    address public immutable DEX;
    uint256 public immutable zapFeeBPS;
    address public immutable zapFeeReceiver;

    constructor(
        IEbtcLeverageZapRouter.DeploymentParams memory params
    )
        ZapRouterBase(
            params.borrowerOperations, 
            IERC20(params.wstEth), 
            IERC20(params.weth), 
            IStETH(params.stEth)
        )
        LeverageMacroBase(
            params.borrowerOperations,
            params.activePool,
            params.cdpManager,
            params.ebtc,
            params.stEth,
            params.sortedCdps,
            false // Do not sweep
        )
    {
        if (params.zapFeeBPS > 0) {
            require(params.zapFeeReceiver != address(0));
        }

        theOwner = params.owner;
        DEX = params.dex;
        zapFeeBPS = params.zapFeeBPS;
        zapFeeReceiver = params.zapFeeReceiver;

        // Infinite Approvals @TODO: do these stay at max for each token?
        ebtcToken.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(activePool), type(uint256).max);
        stEth.approve(address(wstEth), type(uint256).max);
    }

    function owner() public override returns (address) {
        return theOwner;
    }

    function doOperation(
        FlashLoanType flType,
        uint256 borrowAmount,
        LeverageMacroOperation calldata operation,
        PostOperationCheck postCheckType,
        PostCheckParams calldata checkParams
    ) external override {
        // prevents the owner from doing arbitrary calls
        revert("disabled");
    }

    function _sweepEbtc() private {
        /**
         * SWEEP TO CALLER *
         */
        // Safe unchecked because known tokens
        uint256 bal = ebtcToken.balanceOf(address(this));

        if (bal > 0) {
            ebtcToken.transfer(msg.sender, bal);
        }
    }

    function _sweepStEth() private {
        /**
         * SWEEP TO CALLER *
         */
        // Safe unchecked because known tokens
        uint256 bal = stEth.sharesOf(address(this));

        if (bal > 0) {
            stEth.transferShares(msg.sender, bal);
        }
    }

    function _getAdjustCdpParams(
        AdjustCdpOperation memory _cdp,
        TradeData calldata _tradeData
    ) private view returns (LeverageMacroOperation memory op) {
        op.tokenToTransferIn = address(stETH);
        // collateral already transferred in by the caller
        op.amountToTransferIn = 0;
        op.operationType = OperationType.AdjustCdpOperation;
        op.OperationData = abi.encode(_cdp);

        // This router is only intended to be used for operations
        // that involve flash loans. The UI will route all unleveraged
        // operations to the normal EbtcZapRouter
        if (_cdp._isDebtIncrease) {
            // for debt increases, we flash borrow stETH
            // trade eBTC -> stETH for repayment
            op.swapsAfter = _getSwapOperations(
                address(ebtcToken), 
                address(stETH),
                _tradeData
            );
        } else {
            // for debt decreases (unwinding), we flash borrow eBTC
            // trade stETH -> eBTC for repayment
            op.swapsAfter = _getSwapOperations(
                address(stETH),
                address(ebtcToken),
                _tradeData
            );
        }
    }

    function _adjustCdpOperation(
        bytes32 _cdpId,
        FlashLoanType _flType,
        uint256 _flAmount,
        AdjustCdpOperation memory _cdp,
        uint256 debt,
        uint256 coll,
        TradeData calldata _tradeData
    ) internal {
        uint256 newDebt = _cdp._isDebtIncrease ? debt + _cdp._EBTCChange : debt - _cdp._EBTCChange;
        uint256 newColl = _cdp._stEthBalanceIncrease > 0 ? 
            coll + stEth.getSharesByPooledEth(_cdp._stEthBalanceIncrease) : 
            coll - stEth.getSharesByPooledEth(_cdp._stEthBalanceDecrease);

        _doOperation(
            _flType,
            _flAmount,
            _getAdjustCdpParams(_cdp, _tradeData),
            PostOperationCheck.cdpStats,
            _getPostCheckParams(
                _cdpId, 
                newDebt, 
                newColl, 
                ICdpManagerData.Status.active,
                _tradeData.collValidationBufferBPS
            ),
            _cdpId
        );

        _sweepEbtc();
        // sweepStEth happens outside of this call
    }

    function _openCdpOperation(
        bytes32 _cdpId,
        OpenCdpForOperation memory _cdp,
        uint256 _flAmount,
        TradeData calldata _tradeData
    ) internal {
        LeverageMacroOperation memory op;

        op.tokenToTransferIn = address(stETH);
        // collateral already transferred in by the caller
        op.amountToTransferIn = 0;
        op.operationType = OperationType.OpenCdpForOperation;
        op.OperationData = abi.encode(_cdp);
        op.swapsAfter = _getSwapOperations(address(ebtcToken), address(stETH), _tradeData);

        _doOperation(
            FlashLoanType.stETH,
            _flAmount,
            op,
            PostOperationCheck.openCdp,
            _getPostCheckParams(
                _cdpId,
                _cdp.eBTCToMint,
                stETH.getSharesByPooledEth(_cdp.stETHToDeposit),
                ICdpManagerData.Status.active,
                _tradeData.collValidationBufferBPS

            ),
            _cdpId
        );

        _sweepEbtc();
        _sweepStEth();
    }

    function _closeCdpOperation(
        bytes32 _cdpId,
        uint256 _debt,
        TradeData calldata _tradeData
    ) internal {
        CloseCdpOperation memory cdp;

        cdp._cdpId = _cdpId;

        LeverageMacroOperation memory op;

        op.operationType = OperationType.CloseCdpOperation;
        op.OperationData = abi.encode(cdp);
        op.swapsAfter = _getSwapOperations(
            address(stETH),
            address(ebtcToken),
            _tradeData
        );

        _doOperation(
            FlashLoanType.eBTC,
            _debt,
            op,
            PostOperationCheck.isClosed,
            _getPostCheckParams(_cdpId, 0, 0, ICdpManagerData.Status.closedByOwner, 0),
            bytes32(0)
        );

        _sweepEbtc();
        // sweepStEth happens outside of this call
    }

    function _getSwapOperations(
        address _tokenIn,
        address _tokenOut,
        TradeData calldata _tradeData
    ) internal view returns (SwapOperation[] memory swaps) {
        swaps = new SwapOperation[](1);

        swaps[0].tokenForSwap = _tokenIn;
        swaps[0].addressForApprove = DEX;
        swaps[0].exactApproveAmount = _tradeData.approvalAmount;
        swaps[0].addressForSwap = DEX;
        swaps[0].calldataForSwap = _tradeData.exchangeData;
        if (_tradeData.performSwapChecks) {
            swaps[0].swapChecks = _getSwapChecks(_tokenOut, _tradeData.expectedMinOut);            
        }
    }

    function _getSwapChecks(address tokenToCheck, uint256 expectedMinOut) 
        internal view returns (SwapCheck[] memory checks) {
        checks = new SwapCheck[](1);

        checks[0].tokenToCheck = tokenToCheck;
        checks[0].expectedMinOut = expectedMinOut;
    }

    function _getPostCheckParams(
        bytes32 _cdpId,
        uint256 _debt,
        uint256 _totalCollateral,
        ICdpManagerData.Status _status,
        uint256 _collValidationBuffer
    ) internal view returns (PostCheckParams memory) {
        return
            PostCheckParams({
                expectedDebt: CheckValueAndType({value: _debt, operator: Operator.equal}),
                expectedCollateral: CheckValueAndType({
                    value:  _totalCollateral * _collValidationBuffer / BPS,
                    operator: Operator.gte
                }),
                cdpId: _cdpId,
                expectedStatus: _status
            });
    }

    function _openCdpForCallback(bytes memory data) internal override {
        if (zapFeeBPS > 0) {
            OpenCdpForOperation memory flData = abi.decode(data, (OpenCdpForOperation));

            bytes32 _cdpId = borrowerOperations.openCdpFor(
                flData.eBTCToMint,
                flData._upperHint,
                flData._lowerHint,
                flData.stETHToDeposit,
                flData.borrower
            );

            IERC20(address(ebtcToken)).safeTransfer(zapFeeReceiver, flData.eBTCToMint * zapFeeBPS / BPS);
        } else {
            super._openCdpForCallback(data);
        }
    }

    function _adjustCdpCallback(bytes memory data) internal override {
        if (zapFeeBPS > 0) {
            AdjustCdpOperation memory flData = abi.decode(data, (AdjustCdpOperation));

            borrowerOperations.adjustCdpWithColl(
                flData._cdpId,
                flData._stEthBalanceDecrease,
                flData._EBTCChange,
                flData._isDebtIncrease,
                flData._upperHint,
                flData._lowerHint,
                flData._stEthBalanceIncrease
            );

            if (flData._isDebtIncrease) {
                IERC20(address(ebtcToken)).safeTransfer(zapFeeReceiver, flData._EBTCChange * zapFeeBPS / BPS);
            }
        } else {
            super._adjustCdpCallback(data);
        }
    }
}
