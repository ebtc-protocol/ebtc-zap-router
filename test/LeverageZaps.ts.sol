// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {EbtcZapRouter} from "../src/EbtcZapRouter.sol";
import {ZapRouterBaseInvariants} from "./ZapRouterBaseInvariants.sol";
import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";
import {IEbtcZapRouter} from "../src/interface/IEbtcZapRouter.sol";


contract LeverageZaps is ZapRouterBaseInvariants {
    function setUp() public override {
        super.setUp();
    }

    function test_ZapOpenCdp_WithStEth_LowLeverage() public {
        console2.logUint(zapRouter.temp_RequiredCollateral(1e18));
    }
}