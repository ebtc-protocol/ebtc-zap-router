// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManagerData.sol";

interface ILeverageMacroBase {
    enum FlashLoanType {
        stETH,
        eBTC,
        noFlashloan // Use this to not perform a FL and just `doOperation`
    }

    enum PostOperationCheck {
        none,
        openCdp,
        cdpStats,
        isClosed
    }

    enum Operator {
        skip,
        equal,
        gte,
        lte
    }

    struct CheckValueAndType {
        uint256 value;
        Operator operator;
    }

    struct PostCheckParams {
        CheckValueAndType expectedDebt;
        CheckValueAndType expectedCollateral;
        // Used only if cdpStats || isClosed
        bytes32 cdpId;
        // Used only to check status
        ICdpManagerData.Status expectedStatus; // NOTE: THIS IS SUPERFLUOUS
    }  

    struct LeverageMacroOperation {
        address tokenToTransferIn;
        uint256 amountToTransferIn;
        SwapOperation[] swapsBefore; // Empty to skip
        SwapOperation[] swapsAfter; // Empty to skip
        OperationType operationType; // Open, Close, etc..
        bytes OperationData; // Generic Operation Data, which we'll decode to use
    }

    struct SwapOperation {
        // Swap Data
        address tokenForSwap;
        address addressForApprove;
        uint256 exactApproveAmount;
        address addressForSwap;
        bytes calldataForSwap;
        SwapCheck[] swapChecks; // Empty to skip
    }

    struct SwapCheck {
        // Swap Slippage Check
        address tokenToCheck;
        uint256 expectedMinOut;
    }

    enum OperationType {
        None, // Swaps only
        OpenCdpOperation,
        OpenCdpForOperation,
        AdjustCdpOperation,
        CloseCdpOperation,
        ClaimSurplusOperation
    }

    // Open
    struct OpenCdpOperation {
        // Open CDP For Data
        uint256 eBTCToMint;
        bytes32 _upperHint;
        bytes32 _lowerHint;
        uint256 stETHToDeposit;
    }

    // Open for
    struct OpenCdpForOperation {
        // Open CDP For Data
        uint256 eBTCToMint;
        bytes32 _upperHint;
        bytes32 _lowerHint;
        uint256 stETHToDeposit;
        address borrower;
    }

    // Change leverage or something
    struct AdjustCdpOperation {
        bytes32 _cdpId;
        uint256 _stEthBalanceDecrease;
        uint256 _EBTCChange;
        bool _isDebtIncrease;
        bytes32 _upperHint;
        bytes32 _lowerHint;
        uint256 _stEthBalanceIncrease;
    }

    // Repay and Close
    struct CloseCdpOperation {
        bytes32 _cdpId;
    } 
}
