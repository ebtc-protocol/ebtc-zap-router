// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IEbtcZapRouterBase} from "./IEbtcZapRouterBase.sol";

interface IEbtcLeverageZapRouter is IEbtcZapRouterBase {
    struct DeploymentParams {
        address borrowerOperations;
        address activePool;
        address cdpManager;
        address ebtc;
        address stEth;
        address weth;
        address wstEth;
        address sortedCdps;
        address priceFeed;
        address dex;
    }

    struct AdjustCdpParams {
        uint256 _ebtcLoanAmount;
        uint256 _debtChange;
        bool _isDebtIncrease;
        bytes32 _upperHint;
        bytes32 _lowerHint;
        uint256 _stEthLoanAmount;
        uint256 _collBalanceDecrease;
        uint256 _collBalanceIncrease;
        bool _useWstETHForDecrease;
    }
}
