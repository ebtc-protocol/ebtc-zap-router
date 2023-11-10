// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {EbtcZapRouter} from "../src/EbtcZapRouter.sol";
import {ZapRouterBaseInvariants} from "./ZapRouterBaseInvariants.sol";
import {IEbtcZapRouter} from "../src/interface/IEbtcZapRouter.sol";

contract NoLeverageZaps is ZapRouterBaseInvariants {
    function setUp() public override {
        super.setUp();
    }

    ///@dev test case: open CDP with stETH collateral
    ///@dev PositionManager should be valid until deadline
    function test_ZapOpenCdp_WithStEth_NoLeverage_NoFlippening() public {
        address user = TEST_FIXED_USER;

        _dealCollateralAndPrepForUse(user);

        uint256 stEthBalance = 30 ether;

        uint256 debt = _utils.calculateBorrowAmount(
            stEthBalance,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );

        vm.startPrank(user);

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();

        collateral.approve(address(zapRouter), type(uint256).max);

        // Get before balances

        // Zap Open Cdp
        uint256 _cdpCntBefore = sortedCdps.cdpCountOf(user);
        zapRouter.openCdp(
            debt,
            bytes32(0),
            bytes32(0),
            stEthBalance + 0.2 ether,
            pmPermit
        );

        // Confirm Cdp opened for user
        uint256 _cdpCntAfter = sortedCdps.cdpCountOf(user);
        assertEq(_cdpCntAfter - _cdpCntBefore, 1, "User should have 1 new cdp");

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: open CDP with raw native Ether
    function test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening() public {
        address user = TEST_FIXED_USER;

        _dealRawEtherForUser(user);

        uint256 stEthBalance = 30 ether;

        uint256 debt = _utils.calculateBorrowAmount(
            stEthBalance,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );

        vm.startPrank(user);

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();

        // Get before balances

        // Zap Open Cdp
        uint256 _cdpCntBefore = sortedCdps.cdpCountOf(user);
        uint256 _initialETH = stEthBalance + 0.2 ether;
        zapRouter.openCdpWithEth{value: _initialETH}(
            debt,
            bytes32(0),
            bytes32(0),
            _initialETH,
            pmPermit
        );

        // Confirm Cdp opened for user
        uint256 _cdpCntAfter = sortedCdps.cdpCountOf(user);
        assertEq(_cdpCntAfter - _cdpCntBefore, 1, "User should have 1 new cdp");

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: close CDP
    function test_ZapCloseCdp_NoLeverage_NoFlippening() public {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        // open anther CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToClose = sortedCdps.cdpOfOwnerByIndex(user, 0);
        assertEq(
            cdpManager.getCdpStatus(_cdpIdToClose),
            1,
            "Cdp should be active for now"
        );

        vm.startPrank(user);
        IERC20(address(eBTCToken)).approve(
            address(zapRouter),
            type(uint256).max
        );

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();
        zapRouter.closeCdp(_cdpIdToClose, pmPermit);
        assertEq(
            cdpManager.getCdpStatus(_cdpIdToClose),
            2,
            "Cdp should be closedByOwner at this moment"
        );

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: increase collateral with raw native Ether for CDP
    function test_ZapAddCollWithRawEth_NoLeverage_NoFlippening() public {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToAddColl = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAddColl
        );

        vm.startPrank(user);
        uint256 _addedColl = 2 ether;

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();
        zapRouter.addCollWithEth{value: _addedColl}(
            _cdpIdToAddColl,
            bytes32(0),
            bytes32(0),
            _addedColl,
            pmPermit
        );
        uint256 _collShareAfter = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAddColl
        );
        assertEq(
            _collShareBefore + collateral.getSharesByPooledEth(_addedColl),
            _collShareAfter,
            "Cdp collateral should be added as expected at this moment"
        );

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: withdraw collateral from the CDP
    function test_ZapReduceColl_NoLeverage_NoFlippening() public {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToReduceColl = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToReduceColl
        );

        vm.startPrank(user);
        uint256 _stETHBalBefore = collateral.balanceOf(user);
        uint256 _reducedColl = 2 ether;

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();
        zapRouter.adjustCdp(
            _cdpIdToReduceColl,
            _reducedColl,
            0,
            false,
            bytes32(0),
            bytes32(0),
            0,
            pmPermit
        );
        
        uint256 _stETHBalAfter = collateral.balanceOf(user);
        uint256 _collShareAfter = cdpManager.getSyncedCdpCollShares(
            _cdpIdToReduceColl
        );
        assertEq(
            _collShareBefore - collateral.getSharesByPooledEth(_reducedColl),
            _collShareAfter,
            "Cdp collateral should be reduced as expected at this moment"
        );
        assertEq(
            _stETHBalBefore + _reducedColl,
            _stETHBalAfter,
            "Collateral should be withdrawn to user as expected at this moment"
        );

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }
}
