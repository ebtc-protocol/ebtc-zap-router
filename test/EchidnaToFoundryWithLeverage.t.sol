// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {FoundryAsserts} from "@ebtc/foundry_test/utils/FoundryAsserts.sol";
import "./invariants/TargetFunctionsWithLeverage.sol";

contract EchidnaToFoundryWithLeverage is FoundryAsserts, TargetFunctionsWithLeverage {
    function setUp() public override {
        super.setUp();
        super.setUpActors();
    }

    modifier setup() override {
        zapSender = zapActorAddrs[0];
        zapActor = zapActors[zapActorAddrs[0]];
        zapActorKey = zapActorKeys[zapActorAddrs[0]];
        _;
    }

    function test_adjustDebt_broken() public {
        openCdpWithWstEth(
            10000000000000000, 
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );
        openCdpWithEth(50, 22472026438745993630649141679288895886816134194585710289921016214117135640789);
        setEthPerShare(0);
        openCdpWithEth(644007913129035136, 115792089237316195423570985008687907853269984665640564039457584007913123591936);
        openCdpWithWstEth(1000000000000000000000000, 29271164062172996603782634127007672391705299194166817769298549212157347143267);
        openCdpWithWstEth(0, 54927740400986167749634435283977843215123076379569166179371083812776248289552);
        openCdpWithWrappedEth(1100000000000196608, 53717814670755525736871604781075091403719411083512021580229803075787966963112);
        setEthPerShare(50);
        adjustDebt(
            999037758833783000, 
            30781141190554274141259347257730390064032396717553110677262331543245600510722, 
            true, 
            22173519360197739664592590818540540018811991597990649936523158196068588522133, 
            false
        );
    }
}
