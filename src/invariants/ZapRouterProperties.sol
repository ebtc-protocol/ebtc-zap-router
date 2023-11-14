pragma solidity 0.8.17;

import {ZapRouterStateSnapshots} from "./ZapRouterStateSnapshots.sol";
import {ZapRouterPropertiesDescriptions} from "./ZapRouterPropertiesDescriptions.sol";
import {EchidnaAsserts} from "@ebtc/contracts/TestContracts/invariants/echidna/EchidnaAsserts.sol";

abstract contract ZapRouterProperties is
    ZapRouterStateSnapshots,
    ZapRouterPropertiesDescriptions,
    EchidnaAsserts
{
    function echidna_ZR_01() public returns (bool) {
        return
            (collateral.sharesOf(address(zapRouter)) == 0) &&
            (collateral.balanceOf(address(zapRouter)) == 0) &&
            (eBTCToken.balanceOf(address(zapRouter)) == 0);
    }
}
