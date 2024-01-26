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

abstract contract LeverageZapRouterBase is ZapRouterBase, LeverageMacroBase, ReentrancyGuard {
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

    function _sweep() private {
        /**
         * SWEEP TO CALLER *
         */
        // Safe unchecked because known tokens
        uint256 ebtcBal = ebtcToken.balanceOf(address(this));
        uint256 collateralBal = stETH.sharesOf(address(this));

        if (ebtcBal > 0) {
            ebtcToken.transfer(msg.sender, ebtcBal);
        }

        if (collateralBal > 0) {
            stETH.transferShares(msg.sender, collateralBal);
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
        bytes calldata _exchangeData
    ) internal {
        LeverageMacroOperation memory op;

        op.tokenToTransferIn = address(stETH);
        op.amountToTransferIn = _marginIncrease;
        op.operationType = OperationType.AdjustCdpOperation;
        op.OperationData = abi.encode(_cdp);

        if (_cdp._isDebtIncrease) {
            op.swapsAfter = _getSwapOperations(address(ebtcToken), _cdp._EBTCChange, _exchangeData);
        } else {
            op.swapsAfter = _getSwapOperations(
                address(stETH),
                _cdp._stEthBalanceDecrease,
                _exchangeData
            );
        }

        _doOperation(
            _flType,
            _flAmount,
            op,
            PostOperationCheck.cdpStats,
            _getPostCheckParams(_cdpId, newDebt, newColl, ICdpManagerData.Status.active),
            _cdpId
        );

        // TODO: only sweep diff
        _sweep();
    }

    function _openCdpOperation(
        bytes32 _cdpId,
        OpenCdpForOperation memory _cdp,
        uint256 _flAmount,
        uint256 _stEthBalance,
        bytes calldata _exchangeData
    ) internal {
        LeverageMacroOperation memory op;

        op.tokenToTransferIn = address(stETH);
        op.amountToTransferIn = _stEthBalance;
        op.operationType = OperationType.OpenCdpForOperation;
        op.OperationData = abi.encode(_cdp);
        op.swapsAfter = _getSwapOperations(address(ebtcToken), _cdp.eBTCToMint, _exchangeData);

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

        // TODO: only sweep diff
        _sweep();
    }

    function _closeCdpOperation(
        bytes32 _cdpId,
        uint256 _debt,
        uint256 _stEthAmount,
        bytes calldata _exchangeData
    ) internal {
        CloseCdpOperation memory cdp;

        cdp._cdpId = _cdpId;

        LeverageMacroOperation memory op;

        op.operationType = OperationType.CloseCdpOperation;
        op.OperationData = abi.encode(cdp);
        op.swapsAfter = _getSwapOperations(
            address(stETH),
            // This is an exact out trade, so we specify the max collateral
            // amount the DEX is allowed to pull
            _stEthAmount,
            _exchangeData
        );

        _doOperation(
            FlashLoanType.eBTC,
            _debt,
            op,
            PostOperationCheck.isClosed,
            _getPostCheckParams(_cdpId, 0, 0, ICdpManagerData.Status.closedByOwner),
            bytes32(0)
        );

        // TODO: only sweep diff
        _sweep();
    }

    function _getSwapOperations(
        address _tokenForSwap,
        uint256 _exactApproveAmount,
        bytes calldata _exchangeData
    ) internal view returns (SwapOperation[] memory swaps) {
        swaps = new SwapOperation[](1);

        swaps[0].tokenForSwap = _tokenForSwap;
        // TODO: approve target maybe different
        swaps[0].addressForApprove = dex;
        swaps[0].exactApproveAmount = _exactApproveAmount;
        swaps[0].addressForSwap = dex;
        // TODO: exchange data needs to be passed in for aggregators (i.e. ZeroEx)
        // this trade can be generated for now
        swaps[0].calldataForSwap = _exchangeData;
        // op.swapChecks TODO: add proper checks
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
