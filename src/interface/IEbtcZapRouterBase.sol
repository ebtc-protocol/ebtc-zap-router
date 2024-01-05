// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IEbtcZapRouterBase {
    struct PositionManagerPermit {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }
}
