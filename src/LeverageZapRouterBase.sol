// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IPositionManagers} from "@ebtc/contracts/Interfaces/IBorrowerOperations.sol";
import {IPriceFeed} from "@ebtc/contracts/Interfaces/IPriceFeed.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {LeverageMacroBase} from "@ebtc/contracts/LeverageMacroBase.sol";
import {ReentrancyGuard} from "@ebtc/contracts/Dependencies/ReentrancyGuard.sol";
import {IEbtcLeverageZapRouter} from "./interface/IEbtcLeverageZapRouter.sol";
import {ZapRouterBase} from "./ZapRouterBase.sol";
import {IStETH} from "./interface/IStETH.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";

abstract contract LeverageZapRouterBase is ZapRouterBase, LeverageMacroBase, ReentrancyGuard, IEbtcLeverageZapRouter {
    uint256 internal constant PRECISION = 1e18;

    address internal immutable theOwner;
    IPriceFeed internal immutable priceFeed;
    address internal immutable dex;

    constructor(
        IEbtcLeverageZapRouter.DeploymentParams memory params
    )
        ZapRouterBase(IERC20(params.wstEth), IERC20(params.weth), IStETH(params.stEth))
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
        theOwner = msg.sender;
        priceFeed = IPriceFeed(params.priceFeed);
        dex = params.dex;

        // Infinite Approvals @TODO: do these stay at max for each token?
        ebtcToken.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(activePool), type(uint256).max);
    }

    function owner() public override returns (address) {
        return theOwner;
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

    function _debtToCollateral(uint256 _debt) public returns (uint256) {
        uint256 price = priceFeed.fetchPrice();
        return (_debt * PRECISION) / price;
    }

    function _adjustCdpOperation(
        bytes32 _cdpId,
        FlashLoanType _flType,
        uint256 _flAmount,
        uint256 _marginIncrease,
        AdjustCdpOperation memory _cdp,
        uint256 newDebt,
        uint256 newColl,
        TradeData calldata _tradeData
    ) internal {
        LeverageMacroOperation memory op;

        op.tokenToTransferIn = address(stETH);
        op.amountToTransferIn = _marginIncrease;
        op.operationType = OperationType.AdjustCdpOperation;
        op.OperationData = abi.encode(_cdp);

        if (_cdp._isDebtIncrease) {
            op.swapsAfter = _getSwapOperations(
                address(ebtcToken), 
                address(stETH),
                _cdp._EBTCChange, 
                _tradeData
            );
        } else {
            // Only swap if we are decreasing collateral
            if (_cdp._stEthBalanceDecrease > 0) {
                op.swapsAfter = _getSwapOperations(
                    address(stETH),
                    address(ebtcToken),
                    _cdp._stEthBalanceDecrease,
                    _tradeData
                );
            }
        }

        _doOperation(
            _flType,
            _flAmount,
            op,
            PostOperationCheck.cdpStats,
            _getPostCheckParams(_cdpId, newDebt, newColl, ICdpManagerData.Status.active),
            _cdpId
        );

        _sweepEbtc();
    }

    function _openCdpOperation(
        bytes32 _cdpId,
        OpenCdpForOperation memory _cdp,
        uint256 _flAmount,
        uint256 _stEthBalance,
        TradeData calldata _tradeData
    ) internal {
        LeverageMacroOperation memory op;

        op.tokenToTransferIn = address(stETH);
        op.amountToTransferIn = _stEthBalance;
        op.operationType = OperationType.OpenCdpForOperation;
        op.OperationData = abi.encode(_cdp);
        op.swapsAfter = _getSwapOperations(address(ebtcToken), address(stETH), _cdp.eBTCToMint, _tradeData);

        uint256 ebtcBalBefore = ebtcToken.balanceOf(address(this));
        _doOperation(
            FlashLoanType.stETH,
            _flAmount,
            op,
            PostOperationCheck.openCdp,
            _getPostCheckParams(
                _cdpId,
                _cdp.eBTCToMint,
                _cdp.stETHToDeposit,
                ICdpManagerData.Status.active
            ),
            _cdpId
        );

        _sweepEbtc();
        _sweepStEth();
    }

    function _closeCdpOperation(
        bytes32 _cdpId,
        uint256 _debt,
        uint256 _stEthAmount,
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
            _stEthAmount,
            _tradeData
        );

        _doOperation(
            FlashLoanType.eBTC,
            _debt,
            op,
            PostOperationCheck.isClosed,
            _getPostCheckParams(_cdpId, 0, 0, ICdpManagerData.Status.closedByOwner),
            bytes32(0)
        );

        _sweepEbtc();
    }

    function _getSwapOperations(
        address _tokenIn,
        address _tokenOut,
        uint256 _exactApproveAmount,
        TradeData calldata _tradeData
    ) internal view returns (SwapOperation[] memory swaps) {
        swaps = new SwapOperation[](1);

        swaps[0].tokenForSwap = _tokenIn;
        // TODO: approve target maybe different
        swaps[0].addressForApprove = dex;
        swaps[0].exactApproveAmount = _exactApproveAmount;
        swaps[0].addressForSwap = dex;
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
        ICdpManagerData.Status _status
    ) internal view returns (PostCheckParams memory) {
        return
            PostCheckParams({
                expectedDebt: CheckValueAndType({value: _debt, operator: Operator.equal}),
                expectedCollateral: CheckValueAndType({
                    value: _totalCollateral,
                    operator: Operator.skip
                }),
                cdpId: _cdpId,
                expectedStatus: _status
            });
    }
}
