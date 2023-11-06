pragma solidity 0.8.17;

import {ZapRouterStateSnapshots} from "./ZapRouterStateSnapshots.sol";
import {ZapRouterPropertiesDescriptions} from "./ZapRouterPropertiesDescriptions.sol";
import {Asserts} from "@ebtc/contracts/TestContracts/invariants/Asserts.sol";

abstract contract ZapRouterProperties is ZapRouterStateSnapshots, ZapRouterPropertiesDescriptions, Asserts {
}
