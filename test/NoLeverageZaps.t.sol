// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {EbtcZapRouter} from "../src/EbtcZapRouter.sol";
import {ZapRouterBaseInvariants} from "./ZapRouterBaseInvariants.sol";
import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";


contract NoLeverageZaps is ZapRouterBaseInvariants {
    function setUp() public override {
        super.setUp();
    }

    ///@dev PositionManager should be valid until deadline
    function test_ZapOpenCdp_WithStEth_NoLeverage_NoFlippening() public {
        address user = _createUserFromFixedPrivateKey();

        uint _deadline = (block.timestamp + deadline);
        IPositionManagers.PositionManagerApproval _approval = IPositionManagers
            .PositionManagerApproval
            .OneTime;

         _dealCollateralAndPrepForUse(user);

         uint256 stEthBalance = 30 ether;

         uint256 debt = _utils.calculateBorrowAmount(
            stEthBalance,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );
        
        vm.startPrank(user);

        // Generate signature to one-time approve zap
        bytes32 digest = _generatePermitSignature(user, address(zapRouter), _approval, _deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        // Get before balances

        // Zap Open Cdp
        zapRouter.openCdp(
            debt,
            bytes32(0),
            bytes32(0),
            stEthBalance + 0.2 ether,
            _deadline,
            v,
            r,
            s
        );

        // Confirm Cdp opened
        // Confirm Zap has no cdps
        // Confirm Zap has no coins

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }
}
