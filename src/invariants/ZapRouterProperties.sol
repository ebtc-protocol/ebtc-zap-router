pragma solidity 0.8.17;

import {ZapRouterStateSnapshots} from "./ZapRouterStateSnapshots.sol";
import {ZapRouterPropertiesDescriptions} from "./ZapRouterPropertiesDescriptions.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {Asserts} from "@ebtc/contracts/TestContracts/invariants/Asserts.sol";

abstract contract ZapRouterProperties is
    ZapRouterStateSnapshots,
    ZapRouterPropertiesDescriptions,
    Asserts
{
    uint256 public constant MAX_COLL_ROUNDING_ERROR = 2;

    function echidna_ZR_01() public returns (bool) {
        return eBTCToken.balanceOf(address(zapRouter)) == 0;
    }

    function echidna_ZR_02() public returns (bool) {
        return address(zapRouter).balance == 0;
    }

    function echidna_ZR_03() public returns (bool) {
        return sortedCdps.cdpCountOf(address(zapRouter)) == 0;
    }

    function echidna_ZR_04() public returns (bool) {
        return IERC20(testWeth).balanceOf(address(zapRouter)) == 0;
    }

    function echidna_ZR_05() public returns (bool) {
        return IERC20(testWstEth).balanceOf(address(zapRouter)) == 0;
    }
}
