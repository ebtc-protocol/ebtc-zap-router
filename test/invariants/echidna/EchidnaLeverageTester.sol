// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {EchidnaAsserts} from "@ebtc/contracts/TestContracts/invariants/echidna/EchidnaAsserts.sol";
import {TargetFunctionsWithLeverage} from "../TargetFunctionsWithLeverage.sol";

contract EchidnaLeverageTester is TargetFunctionsWithLeverage, EchidnaAsserts {
    constructor() payable {
        super.setUp();
        super.setUpActors();
    }
}
