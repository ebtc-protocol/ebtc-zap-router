// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {EchidnaAsserts} from "@ebtc/contracts/TestContracts/invariants/echidna/EchidnaAsserts.sol";
import {TargetFunctionsNoLeverage} from "../TargetFunctionsNoLeverage.sol";

contract EchidnaNoLeverageTester is TargetFunctionsNoLeverage, EchidnaAsserts {
    constructor() payable {
        super.setUp();
        super.setUpActors();
    }
}
