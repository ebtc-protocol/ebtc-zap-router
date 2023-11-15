// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {EbtcZapRouter} from "../EbtcZapRouter.sol";
import {ZapRouterActor} from "./ZapRouterActor.sol";
import {BaseStorageVariables} from "@ebtc/contracts/TestContracts/BaseStorageVariables.sol";

abstract contract ZapRouterBaseStorageVariables is BaseStorageVariables {
    EbtcZapRouter public zapRouter;
    uint256 internal constant userPrivateKey = 0xabc123;
    uint256 internal constant deadline = 1800;

    uint256 internal constant USER1_PK = 0xaaaaaa;
    uint256 internal constant USER2_PK = 0xbbbbbb;
    uint256 internal constant USER3_PK = 0xcccccc;

    mapping(address => ZapRouterActor) internal zapActors;
    mapping(address => uint256) internal zapActorKeys;
    address internal zapSender;
    ZapRouterActor internal zapActor;
    uint256 internal zapActorKey;
}
