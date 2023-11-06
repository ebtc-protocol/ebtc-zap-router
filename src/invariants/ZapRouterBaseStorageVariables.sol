// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {EbtcZapRouter} from "../EbtcZapRouter.sol";
import {BaseStorageVariables} from "@ebtc/contracts/TestContracts/BaseStorageVariables.sol";

abstract contract ZapRouterBaseStorageVariables is BaseStorageVariables {
    EbtcZapRouter public zapRouter;
    uint256 internal constant userPrivateKey = 0xabc123;
    uint256 internal constant deadline = 1800;
}
