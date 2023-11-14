// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {TargetFunctions} from "../TargetFunctions.sol";

contract EchidnaTester is TargetFunctions {
    constructor() payable {
        super.setUp();
    }
}
