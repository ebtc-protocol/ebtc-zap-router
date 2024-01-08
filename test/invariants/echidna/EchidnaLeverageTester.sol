// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {TargetFunctionsWithLeverage} from "../TargetFunctionsWithLeverage.sol";

contract EchidnaTester is TargetFunctionsWithLeverage {
    constructor() payable {
        super.setUp();
        super.setUpActors();
    }
}
