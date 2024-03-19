// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {WETH9} from "@ebtc/contracts/TestContracts/WETH9.sol";
import {EbtcZapRouter} from "../src/EbtcZapRouter.sol";
import {ZapRouterBaseInvariants} from "./ZapRouterBaseInvariants.sol";
import {IEbtcZapRouter} from "../src/interface/IEbtcZapRouter.sol";
import {WstETH} from "../src/testContracts/WstETH.sol";
import {IWstETH} from "../src/interface/IWstETH.sol";

contract NoLeverageZaps is ZapRouterBaseInvariants {

    function setUp() public override {
        super.setUp();
    }

    ///@dev test case: open CDP with stETH collateral
    ///@dev PositionManager should be valid until deadline
    function test_ZapOpenCdp_WithStEth_NoLeverage_NoFlippening() public {
        address user = TEST_FIXED_USER;

        _dealCollateralAndPrepForUse(user);

        uint256 stEthBalance = FIXED_COLL_SIZE;

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

        _before();
        zapRouter.openCdp(
            debt,
            bytes32(0),
            bytes32(0),
            stEthBalance + 0.2 ether,
            pmPermit
        );
        _after();

        // Confirm Cdp opened for user
        uint256 _cdpCntAfter = sortedCdps.cdpCountOf(user);
        assertEq(_cdpCntAfter - _cdpCntBefore, 1, "User should have 1 new cdp");

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    function test_ZapOpenCdp_WithStEthRoundingError_NoLeverage_NoFlippening() public {
        address user = TEST_FIXED_USER;

        _dealCollateralAndPrepForUse(user);

        uint256 stEthBalance = FIXED_COLL_SIZE;

        uint256 debt = _utils.calculateBorrowAmount(
            stEthBalance,
            priceFeedMock.fetchPrice(),
            COLLATERAL_RATIO
        );

        collateral.setEthPerShare(0.99e18);

        vm.startPrank(user);

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();

        collateral.approve(address(zapRouter), type(uint256).max);

        // Get before balances

        // Zap Open Cdp
        uint256 _cdpCntBefore = sortedCdps.cdpCountOf(user);

        _before();
        zapRouter.openCdp(
            debt,
            bytes32(0),
            bytes32(0),
            stEthBalance,
            pmPermit
        );
        _after();

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

        uint256 stEthBalance = FIXED_COLL_SIZE;

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

        _before();
        zapRouter.openCdpWithEth{value: _initialETH}(
            debt,
            bytes32(0),
            bytes32(0),
            _initialETH,
            pmPermit
        );
        _after();

        // Confirm Cdp opened for user
        uint256 _cdpCntAfter = sortedCdps.cdpCountOf(user);
        assertEq(_cdpCntAfter - _cdpCntBefore, 1, "User should have 1 new cdp");

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: open CDP with wrapped Ether
    function test_ZapOpenCdp_WithWrappedEth_NoLeverage_NoFlippening() public {
        address user = TEST_FIXED_USER;

        _dealRawEtherForUser(user);
        uint256 _initialWETH = _dealWrappedEtherForUser(user);

        uint256 debt = _utils.calculateBorrowAmount(
            FIXED_COLL_SIZE,
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
        IERC20(testWeth).approve(address(zapRouter), type(uint256).max);

        _before();
        zapRouter.openCdpWithWrappedEth(
            debt,
            bytes32(0),
            bytes32(0),
            _initialWETH,
            pmPermit
        );
        _after();

        // Confirm Cdp opened for user
        uint256 _cdpCntAfter = sortedCdps.cdpCountOf(user);
        assertEq(_cdpCntAfter - _cdpCntBefore, 1, "User should have 1 new cdp");

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: open CDP with wrapped stETH
    function test_ZapOpenCdp_WithWstEth_NoLeverage_NoFlippening() public {
        address user = TEST_FIXED_USER;

        _dealRawEtherForUser(user);
        uint256 _initialWstETH = _dealWrappedStETHForUser(user);

        uint256 debt = _utils.calculateBorrowAmount(
            FIXED_COLL_SIZE,
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
        IERC20(testWstEth).approve(address(zapRouter), type(uint256).max);

        _before();
        zapRouter.openCdpWithWstEth(
            debt,
            bytes32(0),
            bytes32(0),
            _initialWstETH,
            pmPermit
        );
        _after();

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
        uint256 _cdpColl = cdpManager.getSyncedCdpCollShares(_cdpIdToClose) +
            cdpManager.getCdpLiquidatorRewardShares(_cdpIdToClose);
        uint256 _stETHValBefore = IERC20(address(collateral)).balanceOf(user);

        _before();
        zapRouter.closeCdp(_cdpIdToClose, pmPermit);
        _after();

        assertEq(
            cdpManager.getCdpStatus(_cdpIdToClose),
            2,
            "Cdp should be closedByOwner at this moment"
        );
        uint256 _stETHValAfter = IERC20(address(collateral)).balanceOf(user);
        assertEq(
            _stETHValBefore + IWstETH(testWstEth).getStETHByWstETH(_cdpColl),
            _stETHValAfter,
            "Returned collateral to user should be the number as expected"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: close CDP for WstETH returned to CDP owner
    function test_ZapCloseCdpForWstETH_NoLeverage_NoFlippening() public {
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
        uint256 _cdpColl = cdpManager.getSyncedCdpCollShares(_cdpIdToClose) +
            cdpManager.getCdpLiquidatorRewardShares(_cdpIdToClose);
        uint256 _wstETHValBefore = IERC20(address(testWstEth)).balanceOf(user);

        _before();
        zapRouter.closeCdpForWstETH(_cdpIdToClose, pmPermit);
        _after();

        assertEq(
            cdpManager.getCdpStatus(_cdpIdToClose),
            2,
            "Cdp should be closedByOwner at this moment"
        );
        uint256 _wstETHValAfter = IERC20(address(testWstEth)).balanceOf(user);
        assertEq(
            _wstETHValBefore + _cdpColl,
            _wstETHValAfter,
            "Returned collateral to user should be the number as expected"
        );

        _checkZapStatusAfterOperation(user);

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

        _before();
        zapRouter.addCollWithEth{value: _addedColl}(
            _cdpIdToAddColl,
            bytes32(0),
            bytes32(0),
            _addedColl,
            pmPermit
        );
        _after();

        uint256 _collShareAfter = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAddColl
        );
        assertEq(
            _collShareBefore + collateral.getSharesByPooledEth(_addedColl),
            _collShareAfter,
            "Cdp collateral should be added as expected at this moment"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: increase collateral with raw native Ether for CDP
    function test_ZapAddCollWithStEth_NoLeverage_NoFlippening() public {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithStEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToAddColl = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAddColl
        );

        vm.startPrank(user);
        uint256 _addedColl = 2 ether;

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();

        _before();
        zapRouter.adjustCdp(
            _cdpIdToAddColl,
            0,
            0,
            false,
            bytes32(0),
            bytes32(0),
            _addedColl,
            false,
            pmPermit
        );
        _after();

        uint256 _collShareAfter = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAddColl
        );
        assertEq(
            _collShareBefore + collateral.getSharesByPooledEth(_addedColl),
            _collShareAfter,
            "Cdp collateral should be added as expected at this moment"
        );

        _checkZapStatusAfterOperation(user);

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

        _before();
        zapRouter.adjustCdp(
            _cdpIdToReduceColl,
            _reducedColl,
            0,
            false,
            bytes32(0),
            bytes32(0),
            0,
            false,
            pmPermit
        );
        _after();

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

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: adjust CDP with collateral withdrawn and debt repaid
    function test_ZapAdjustCDPWithdrawCollAndRepay_NoLeverage_NoFlippening()
        public
    {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToAdjust = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtBefore = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);

        vm.startPrank(user);
        uint256 _stETHBalBefore = collateral.balanceOf(user);
        uint256 _changeColl = 2 ether;
        uint256 _changeDebt = _debtBefore / 10;

        IERC20(address(eBTCToken)).approve(
            address(zapRouter),
            type(uint256).max
        );

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();

        _before();
        zapRouter.adjustCdpWithEth(
            _cdpIdToAdjust,
            _changeColl,
            _changeDebt,
            false,
            bytes32(0),
            bytes32(0),
            0,
            false,
            pmPermit
        );
        _after();

        uint256 _stETHBalAfter = collateral.balanceOf(user);
        uint256 _collShareAfter = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtAfterRepay = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);
        assertEq(
            _collShareBefore - collateral.getSharesByPooledEth(_changeColl),
            _collShareAfter,
            "Cdp collateral should be reduced as expected at this moment"
        );
        assertEq(
            _stETHBalBefore + _changeColl,
            _stETHBalAfter,
            "Collateral should be withdrawn to user as expected at this moment"
        );
        assertEq(
            _debtBefore - _changeDebt,
            _debtAfterRepay,
            "Debt should be repaid for CDP as expected at this moment"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: adjust CDP with only debt repayment
    function test_ZapAdjustCDPRepayOnly_NoLeverage_NoFlippening()
        public
    {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToAdjust = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtBefore = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);

        vm.startPrank(user);
        uint256 _stETHBalBefore = collateral.balanceOf(user);
        uint256 _changeDebt = _debtBefore / 10;

        IERC20(address(eBTCToken)).approve(
            address(zapRouter),
            type(uint256).max
        );

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();

        _before();
        zapRouter.adjustCdpWithEth(
            _cdpIdToAdjust,
            0,
            _changeDebt,
            false,
            bytes32(0),
            bytes32(0),
            0,
            false,
            pmPermit
        );
        _after();

        uint256 _stETHBalAfter = collateral.balanceOf(user);
        uint256 _collShareAfter = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtAfterRepay = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);
        assertEq(
            _debtBefore - _changeDebt,
            _debtAfterRepay,
            "Debt should be repaid for CDP as expected at this moment"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: adjust CDP with collateral withdrawn in wrapped version(WstETH) and debt repaid
    function test_ZapAdjustCDPWithdrawWrappedCollAndRepay_NoLeverage_NoFlippening()
        public
    {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToAdjust = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtBefore = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);

        vm.startPrank(user);
        uint256 _wstETHBalBefore = IERC20(testWstEth).balanceOf(user);
        uint256 _changeColl = 2 ether;
        uint256 _changeDebt = _debtBefore / 10;

        IERC20(address(eBTCToken)).approve(
            address(zapRouter),
            type(uint256).max
        );

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();

        _before();
        zapRouter.adjustCdpWithEth(
            _cdpIdToAdjust,
            _changeColl,
            _changeDebt,
            false,
            bytes32(0),
            bytes32(0),
            0,
            true,
            pmPermit
        );
        _after();

        uint256 _wstETHBalAfter = IERC20(testWstEth).balanceOf(user);
        uint256 _collShareAfter = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtAfterRepay = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);
        assertEq(
            _collShareBefore - collateral.getSharesByPooledEth(_changeColl),
            _collShareAfter,
            "Cdp collateral should be reduced as expected at this moment"
        );
        assertEq(
            _wstETHBalBefore + collateral.getSharesByPooledEth(_changeColl),
            _wstETHBalAfter,
            "Collateral(wrapped version) should be withdrawn to user as expected at this moment"
        );
        assertEq(
            _debtBefore - _changeDebt,
            _debtAfterRepay,
            "Debt should be repaid for CDP as expected at this moment"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: adjust CDP with collateral withdrawn and debt minted
    function test_ZapAdjustCDPWithdrawCollAndMint_NoLeverage_NoFlippening()
        public
    {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToAdjust = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtBefore = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);

        vm.startPrank(user);
        uint256 _stETHBalBefore = collateral.balanceOf(user);
        uint256 _changeColl = 2 ether;
        uint256 _changeDebt = _debtBefore / 10;

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();
        uint256 _debtBalBeforeMint = IERC20(address(eBTCToken)).balanceOf(user);

        _before();
        zapRouter.adjustCdpWithEth(
            _cdpIdToAdjust,
            _changeColl,
            _changeDebt,
            true,
            bytes32(0),
            bytes32(0),
            0,
            false,
            pmPermit
        );
        _after();

        uint256 _stETHBalAfter = collateral.balanceOf(user);
        uint256 _collShareAfter = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtAfterRepay = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);
        uint256 _debtBalAfterMint = IERC20(address(eBTCToken)).balanceOf(user);
        assertEq(
            _collShareBefore - collateral.getSharesByPooledEth(_changeColl),
            _collShareAfter,
            "Cdp collateral should be reduced as expected at this moment"
        );
        assertEq(
            _stETHBalBefore + _changeColl,
            _stETHBalAfter,
            "Collateral should be withdrawn to user as expected at this moment"
        );
        assertEq(
            _debtBefore + _changeDebt,
            _debtAfterRepay,
            "Debt should be minted for CDP as expected at this moment"
        );
        assertEq(
            _debtBalBeforeMint + _changeDebt,
            _debtBalAfterMint,
            "Minted debt should go to CDP owner as expected at this moment"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: adjust CDP with collateral withdrawn(wrapped version) and debt minted
    function test_ZapAdjustCDPWithdrawWrappedCollAndMint_NoLeverage_NoFlippening()
        public
    {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToAdjust = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtBefore = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);

        vm.startPrank(user);
        uint256 _wstETHBalBefore = IERC20(testWstEth).balanceOf(user);
        uint256 _changeColl = 2 ether;
        uint256 _changeDebt = _debtBefore / 10;

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();
        uint256 _debtBalBeforeMint = IERC20(address(eBTCToken)).balanceOf(user);

        _before();
        zapRouter.adjustCdpWithEth(
            _cdpIdToAdjust,
            _changeColl,
            _changeDebt,
            true,
            bytes32(0),
            bytes32(0),
            0,
            true,
            pmPermit
        );
        _after();

        uint256 _wstETHBalAfter = IERC20(testWstEth).balanceOf(user);
        uint256 _collShareAfter = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtAfterRepay = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);
        uint256 _debtBalAfterMint = IERC20(address(eBTCToken)).balanceOf(user);
        assertEq(
            _collShareBefore - collateral.getSharesByPooledEth(_changeColl),
            _collShareAfter,
            "Cdp collateral should be reduced as expected at this moment"
        );
        assertEq(
            _wstETHBalBefore + collateral.getSharesByPooledEth(_changeColl),
            _wstETHBalAfter,
            "Collateral should be withdrawn to user as expected at this moment"
        );
        assertEq(
            _debtBefore + _changeDebt,
            _debtAfterRepay,
            "Debt should be minted for CDP as expected at this moment"
        );
        assertEq(
            _debtBalBeforeMint + _changeDebt,
            _debtBalAfterMint,
            "Minted debt should go to CDP owner as expected at this moment"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: adjust CDP with raw native Ether deposited and debt minted
    function test_ZapAdjustCDPWithRawEthDepositAndMint_NoLeverage_NoFlippening()
        public
    {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToAdjust = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtBefore = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);

        vm.startPrank(user);
        uint256 _stETHBalBefore = collateral.balanceOf(user);
        uint256 _changeColl = 2 ether;
        uint256 _changeDebt = _debtBefore / 10;

        // Generate signature to one-time approve zap
        uint256 _debtBalBeforeMint = IERC20(address(eBTCToken)).balanceOf(user);
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermitMint = _generateOneTimePermitFromFixedTestUser();

        _before();
        zapRouter.adjustCdpWithEth{value: _changeColl}(
            _cdpIdToAdjust,
            0,
            _changeDebt,
            true,
            bytes32(0),
            bytes32(0),
            _changeColl,
            false,
            pmPermitMint
        );
        _after();

        uint256 _collShareAfterMint = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtAfterMint = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);
        uint256 _debtBalAfterMint = IERC20(address(eBTCToken)).balanceOf(user);
        assertEq(
            _collShareBefore + collateral.getSharesByPooledEth(_changeColl),
            _collShareAfterMint,
            "Cdp collateral should be reduced as expected at this moment"
        );
        assertEq(
            _debtBefore + _changeDebt,
            _debtAfterMint,
            "Debt should be minted for CDP as expected at this moment"
        );
        assertEq(
            _debtBalBeforeMint + _changeDebt,
            _debtBalAfterMint,
            "Minted debt should go to CDP owner as expected at this moment"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: adjust CDP with raw native Ether deposited and debt minted too much
    function test_ZapAdjustCDPWithRawEthDepositAndMintTooMuch_NoLeverage_NoFlippening()
        public
    {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToAdjust = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtBefore = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);

        vm.startPrank(user);
        uint256 _stETHBalBefore = collateral.balanceOf(user);
        uint256 _changeColl = 2 ether;
        uint256 _changeDebt = _debtBefore * 10;

        // Generate signature to one-time approve zap
        uint256 _debtBalBeforeMint = IERC20(address(eBTCToken)).balanceOf(user);
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermitMint = _generateOneTimePermitFromFixedTestUser();
        vm.stopPrank();

        _before();

        vm.expectRevert(
            "BorrowerOperations: An operation that would result in ICR < MCR is not permitted"
        );
        vm.prank(user);
        zapRouter.adjustCdpWithEth{value: _changeColl}(
            _cdpIdToAdjust,
            0,
            _changeDebt,
            true,
            bytes32(0),
            bytes32(0),
            _changeColl,
            false,
            pmPermitMint
        );
        _after();

        _checkZapStatusAfterOperation(user);
    }

    ///@dev test case: raw Eth donation should not work
    function test_ZapReceiveSurplusRawEth() public {
        address user = TEST_FIXED_USER;

        _dealRawEtherForUser(user);

        uint256 stEthBalance = FIXED_COLL_SIZE;

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

        vm.stopPrank();

        uint256 _initialETH = stEthBalance + 0.2 ether;
        uint256 _extraDonation = 1234567890123;

        _before();

        // require exact amout of raw Eth in openCDP
        vm.expectRevert("EbtcZapRouter: Incorrect ETH amount");
        vm.prank(user);

        zapRouter.openCdpWithEth{value: _initialETH + _extraDonation}(
            debt,
            bytes32(0),
            bytes32(0),
            _initialETH,
            pmPermit
        );
        _after();

        // no receive() or fallback() cause transfer failure
        vm.prank(user);
        (bool sent, ) = address(zapRouter).call{value: _extraDonation}("");
        assertEq(sent, false, "Should not allow send Ether directly to Zap");

        _checkZapStatusAfterOperation(user);
    }

    ///@dev test case: adjust CDP with raw native Ether deposited and debt repaid
    function test_ZapAdjustCDPWithRawEthDepositAndRepay_NoLeverage_NoFlippening()
        public
    {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToAdjust = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtBefore = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);

        vm.startPrank(user);
        uint256 _changeColl = 2 ether;
        uint256 _changeDebt = _debtBefore / 10;

        IERC20(address(eBTCToken)).approve(
            address(zapRouter),
            type(uint256).max
        );

        // Generate signature to one-time approve zap
        uint256 _debtBalBeforeMint = IERC20(address(eBTCToken)).balanceOf(user);
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermitMint = _generateOneTimePermitFromFixedTestUser();
        
        _before();
        zapRouter.adjustCdpWithEth{value: _changeColl}(
            _cdpIdToAdjust,
            0,
            _changeDebt,
            false,
            bytes32(0),
            bytes32(0),
            _changeColl,
            false,
            pmPermitMint
        );
        _after();

        uint256 _collShareAfterMint = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtAfterMint = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);
        uint256 _debtBalAfterMint = IERC20(address(eBTCToken)).balanceOf(user);
        assertEq(
            _collShareBefore + collateral.getSharesByPooledEth(_changeColl),
            _collShareAfterMint,
            "Cdp collateral should be reduced as expected at this moment"
        );
        assertEq(
            _debtBefore - _changeDebt,
            _debtAfterMint,
            "Debt should be repaid for CDP as expected at this moment"
        );
        assertEq(
            _debtBalBeforeMint - _changeDebt,
            _debtBalAfterMint,
            "Repaid debt should deducted from CDP owner as expected at this moment"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: adjust CDP with wrapped Ether deposited and debt repaid
    function test_ZapAdjustCDPWithWrappedEthDepositAndRepay_NoLeverage_NoFlippening()
        public
    {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToAdjust = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtBefore = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);

        uint256 _changeColl = 2 ether;
        uint256 _changeWETH = _dealWrappedEtherForUserWithAmount(
            user,
            _changeColl
        );

        vm.startPrank(user);
        uint256 _changeDebt = _debtBefore / 10;

        IERC20(address(eBTCToken)).approve(
            address(zapRouter),
            type(uint256).max
        );

        IERC20(testWeth).approve(address(zapRouter), type(uint256).max);

        // Generate signature to one-time approve zap
        uint256 _debtBalBeforeMint = IERC20(address(eBTCToken)).balanceOf(user);
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermitMint = _generateOneTimePermitFromFixedTestUser();

        _before();
        zapRouter.adjustCdpWithWrappedEth(
            _cdpIdToAdjust,
            0,
            _changeDebt,
            false,
            bytes32(0),
            bytes32(0),
            _changeWETH,
            false,
            pmPermitMint
        );
        _after();

        uint256 _collShareAfterMint = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtAfterMint = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);
        uint256 _debtBalAfterMint = IERC20(address(eBTCToken)).balanceOf(user);
        assertEq(
            _collShareBefore + collateral.getSharesByPooledEth(_changeWETH),
            _collShareAfterMint,
            "Cdp collateral should be reduced as expected at this moment"
        );
        assertEq(
            _debtBefore - _changeDebt,
            _debtAfterMint,
            "Debt should be repaid for CDP as expected at this moment"
        );
        assertEq(
            _debtBalBeforeMint - _changeDebt,
            _debtBalAfterMint,
            "Repaid debt should deducted from CDP owner as expected at this moment"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: adjust CDP with wrapped stETH deposited and debt repaid
    function test_ZapAdjustCDPWithWstEthDepositAndRepay_NoLeverage_NoFlippening()
        public
    {
        address user = TEST_FIXED_USER;

        // open a CDP
        test_ZapOpenCdp_WithRawEth_NoLeverage_NoFlippening();

        bytes32 _cdpIdToAdjust = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtBefore = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);

        uint256 _changeColl = 2 ether;
        uint256 _changeWstETH = _dealWrappedStETHForUserWithAmount(
            user,
            _changeColl
        );

        vm.startPrank(user);
        uint256 _changeDebt = _debtBefore / 10;

        IERC20(address(eBTCToken)).approve(
            address(zapRouter),
            type(uint256).max
        );

        IERC20(testWstEth).approve(address(zapRouter), type(uint256).max);

        // Generate signature to one-time approve zap
        uint256 _debtBalBeforeMint = IERC20(address(eBTCToken)).balanceOf(user);
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermitMint = _generateOneTimePermitFromFixedTestUser();

        _before();
        zapRouter.adjustCdpWithWstEth(
            _cdpIdToAdjust,
            0,
            _changeDebt,
            false,
            bytes32(0),
            bytes32(0),
            _changeWstETH,
            false,
            pmPermitMint
        );
        _after();

        uint256 _collShareAfterMint = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAdjust
        );
        uint256 _debtAfterMint = cdpManager.getSyncedCdpDebt(_cdpIdToAdjust);
        uint256 _debtBalAfterMint = IERC20(address(eBTCToken)).balanceOf(user);
        assertEq(
            _collShareBefore + _changeWstETH,
            _collShareAfterMint,
            "Cdp collateral should be reduced as expected at this moment"
        );
        assertEq(
            _debtBefore - _changeDebt,
            _debtAfterMint,
            "Debt should be repaid for CDP as expected at this moment"
        );
        assertEq(
            _debtBalBeforeMint - _changeDebt,
            _debtBalAfterMint,
            "Repaid debt should deducted from CDP owner as expected at this moment"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }
}
