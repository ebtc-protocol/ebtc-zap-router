// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ZapRouterProperties} from "../../src/invariants/ZapRouterProperties.sol";

abstract contract TargetFunctions is ZapRouterProperties {
    modifier setup() virtual {
        actor = actors[msg.sender];
        _;
    }
}
