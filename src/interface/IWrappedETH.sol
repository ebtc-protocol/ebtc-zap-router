// SPDX-License-Identifier: GPL-3.0

/* See contracts/COMPILERS.md */
pragma solidity 0.8.17;

/// @notice Wrapped ETH (version 9)
/// @dev check https://etherscan.io/token/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2#code
interface IWrappedETH {
    function withdraw(uint wad) external;
    function deposit() external payable;
}
