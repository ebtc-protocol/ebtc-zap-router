// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {FoundryAsserts} from "@ebtc/foundry_test/utils/FoundryAsserts.sol";
import "./invariants/TargetFunctionsWithLeverage.sol";

contract EchidnaToFoundryWithLeverage is FoundryAsserts, TargetFunctionsWithLeverage {
    function setUp() public override {
        super._setUp();
        super._setUpActors();
        zapActor = zapActors[zapActorAddrs[0]];
        vm.startPrank(address(zapActor));
    }
}
