// SPDX-FileCopyrightText: 2020 Lido <info@lido.fi>

// SPDX-License-Identifier: GPL-3.0

/* See contracts/COMPILERS.md */
pragma solidity 0.8.17;

import "@ebtc/contracts/Dependencies/ICollateralToken.sol";

/// @notice Add submit functionality to eBTC stETH interface
interface IStETH is ICollateralToken {
    function submit(address _referral) external payable returns (uint256);
}
