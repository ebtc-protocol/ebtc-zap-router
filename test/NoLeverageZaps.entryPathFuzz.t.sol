// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {WETH9} from "@ebtc/contracts/TestContracts/WETH9.sol";
import {EbtcZapRouter} from "../src/EbtcZapRouter.sol";
import {ZapRouterBaseInvariants} from "./ZapRouterBaseInvariants.sol";
import {IEbtcZapRouter} from "../src/interface/IEbtcZapRouter.sol";
import {WstETH} from "../src/testContracts/WstETH.sol";
import {IWstETH} from "../src/interface/IWstETH.sol";

contract NoLeverageZapsEntryPathFuzz is ZapRouterBaseInvariants {
    uint256 public constant GAS_STIPEND = 0.2 ether;
    uint256 public constant MIN_FUZZ_COLL_SIZE = 3 ether;
    uint256 public constant MAX_FUZZ_COLL_SIZE = 3000000 ether;
    bytes32 public constant ZAP_EVENT_TARGET =
        keccak256(
            "ZapOperationEthVariant(bytes32,uint8,bool,address,uint256,uint256)"
        );
    /// @dev https://github.com/lidofinance/lido-dao/issues/442#issuecomment-1182264205
    uint256 public constant MAX_LOSS = 2;
    uint256 public constant DEFAULT_INDEX = 1e18;

    function setUp() public override {
        super.setUp();
    }

    ///@dev test case: open CDP with raw native Ether
    function test_ZapOpenCdp_WithRawEth_Fuzz(uint256 _collAmt) public {
        address user = TEST_FIXED_USER;

        _dealRawEtherForUser(user);

        uint256 stEthBalance = _rangeInputCollAmount(_collAmt);

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

        vm.recordLogs();

        bytes32 _cdpId = zapRouter.openCdpWithEth{value: _initialETH}(
            debt,
            bytes32(0),
            bytes32(0),
            _initialETH,
            pmPermit
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        _checkLogEvents(entries, DEFAULT_INDEX);

        // Confirm Cdp opened for user
        uint256 _cdpCntAfter = sortedCdps.cdpCountOf(user);
        assertEq(_cdpCntAfter - _cdpCntBefore, 1, "User should have 1 new cdp");

        // Confirm Cdp collateral match input
        uint256 _cdpShareAfter = cdpManager.getSyncedCdpCollShares(_cdpId);
        uint256 _inputShare = collateral.getSharesByPooledEth(stEthBalance);
        assertTrue(
            _checkCollAmtAgainstInput(_cdpId, _cdpShareAfter, _inputShare),
            "1-wei diff exceed!"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: adjust CDP (adding collateral) with raw native Ether
    function test_ZapAddColl_WithRawEth_Fuzz(uint256 _collAmt) public {
        address user = TEST_FIXED_USER;

        test_ZapOpenCdp_WithRawEth_Fuzz(_collAmt);
        bytes32 _cdpIdToAddColl = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAddColl
        );

        // add collateral to the CDP
        vm.startPrank(user);
        uint256 _addedColl = _utils.generateRandomNumber(
            MIN_FUZZ_COLL_SIZE,
            FIXED_COLL_SIZE,
            address(zapRouter)
        );

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();

        vm.recordLogs();
        zapRouter.addCollWithEth{value: _addedColl}(
            _cdpIdToAddColl,
            bytes32(0),
            bytes32(0),
            _addedColl,
            pmPermit
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        _checkLogEvents(entries, DEFAULT_INDEX);

        uint256 _collShareAfter = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAddColl
        );
        uint256 _collShareAdded = collateral.getSharesByPooledEth(_addedColl);
        assertEq(
            _collShareBefore + _collShareAdded,
            _collShareAfter,
            "Cdp collateral should be added as expected at this moment"
        );
        _checkCollAmtAgainstInput(
            _cdpIdToAddColl,
            (_collShareAfter - _collShareBefore),
            _collShareAdded
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: open CDP with wrapped Ether
    function test_ZapOpenCdp_WithWrappedEth_Fuzz(uint256 _collAmt) public {
        address user = TEST_FIXED_USER;

        _dealRawEtherForUser(user);
        uint256 rawEthBalance = _rangeInputCollAmount(_collAmt);
        uint256 _initialWETH = _dealWrappedEtherForUserWithAmount(
            user,
            rawEthBalance
        );

        uint256 debt = _utils.calculateBorrowAmount(
            _initialWETH,
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

        vm.recordLogs();
        bytes32 _cdpId = zapRouter.openCdpWithWrappedEth(
            debt,
            bytes32(0),
            bytes32(0),
            _initialWETH,
            pmPermit
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        _checkLogEvents(entries, DEFAULT_INDEX);

        // Confirm Cdp opened for user
        uint256 _cdpCntAfter = sortedCdps.cdpCountOf(user);
        assertEq(_cdpCntAfter - _cdpCntBefore, 1, "User should have 1 new cdp");

        // Confirm Cdp collateral match input
        uint256 _cdpShareAfter = cdpManager.getSyncedCdpCollShares(_cdpId);
        uint256 _inputShare = collateral.getSharesByPooledEth(
            _initialWETH - GAS_STIPEND
        );
        assertTrue(
            _checkCollAmtAgainstInput(_cdpId, _cdpShareAfter, _inputShare),
            "1-wei diff exceed!"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: adjust CDP (adding collateral) with wrapped Ether
    function test_ZapAddColl_WithWrappedEth_Fuzz(uint256 _collAmt) public {
        address user = TEST_FIXED_USER;

        test_ZapOpenCdp_WithWrappedEth_Fuzz(_collAmt);
        bytes32 _cdpIdToAddColl = sortedCdps.cdpOfOwnerByIndex(user, 0);
        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAddColl
        );

        // add collateral to the CDP
        uint256 _addedColl = _utils.generateRandomNumber(
            MIN_FUZZ_COLL_SIZE,
            FIXED_COLL_SIZE,
            address(zapRouter)
        );
        uint256 _changeWETH = _dealWrappedEtherForUserWithAmount(
            user,
            _addedColl
        );

        vm.startPrank(user);
        IERC20(testWeth).approve(address(zapRouter), type(uint256).max);

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();

        vm.recordLogs();
        zapRouter.adjustCdpWithWrappedEth(
            _cdpIdToAddColl,
            0,
            0,
            false,
            bytes32(0),
            bytes32(0),
            _changeWETH,
            false,
            pmPermit
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        _checkLogEvents(entries, DEFAULT_INDEX);

        uint256 _collShareAfter = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAddColl
        );
        uint256 _collShareAdded = collateral.getSharesByPooledEth(_changeWETH);
        assertEq(
            _collShareBefore + _collShareAdded,
            _collShareAfter,
            "Cdp collateral should be added as expected at this moment"
        );
        _checkCollAmtAgainstInput(
            _cdpIdToAddColl,
            (_collShareAfter - _collShareBefore),
            _collShareAdded
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: open CDP with wrapped stETH
    function test_ZapOpenCdp_WithWrappedStEth_Fuzz(uint256 _collAmt) public {
        address user = TEST_FIXED_USER;

        _dealRawEtherForUser(user);
        uint256 rawEthBalance = _rangeInputCollAmount(_collAmt);
        uint256 _initialWstETH = _dealWrappedStETHForUserWithAmount(
            user,
            rawEthBalance
        );

        // increase a bit for collateral index
        uint256 _newIdx = 1100000000000000000;
        collateral.setEthPerShare(_newIdx);
        uint256 debt = _utils.calculateBorrowAmount(
            collateral.getPooledEthByShares(_initialWstETH),
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

        vm.recordLogs();
        bytes32 _cdpId = zapRouter.openCdpWithWstEth(
            debt,
            bytes32(0),
            bytes32(0),
            _initialWstETH,
            pmPermit
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        _checkLogEvents(entries, _newIdx);

        // Confirm Cdp opened for user
        uint256 _cdpCntAfter = sortedCdps.cdpCountOf(user);
        assertEq(_cdpCntAfter - _cdpCntBefore, 1, "User should have 1 new cdp");

        // Confirm Cdp collateral match input
        uint256 _cdpShareAfter = cdpManager.getSyncedCdpCollShares(_cdpId);
        uint256 _inputShare = _initialWstETH -
            collateral.getSharesByPooledEth(GAS_STIPEND);
        assertTrue(
            _checkCollAmtAgainstInput(_cdpId, _cdpShareAfter, _inputShare),
            "1-wei diff exceed!"
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    ///@dev test case: adjust CDP (adding collateral) with wrapped stETH
    function test_ZapAddColl_WithWrappedStEth_Fuzz(uint256 _collAmt) public {
        address user = TEST_FIXED_USER;

        test_ZapOpenCdp_WithWrappedStEth_Fuzz(_collAmt);
        bytes32 _cdpIdToAddColl = sortedCdps.cdpOfOwnerByIndex(user, 0);

        // add collateral to the CDP
        uint256 _newIdx = 1110000000000000000;
        collateral.setEthPerShare(_newIdx);

        uint256 _addedColl = _utils.generateRandomNumber(
            MIN_FUZZ_COLL_SIZE,
            FIXED_COLL_SIZE,
            address(zapRouter)
        );
        uint256 _changeWstETH = _dealWrappedStETHForUserWithAmount(
            user,
            _addedColl
        );

        vm.startPrank(user);
        IERC20(testWstEth).approve(address(zapRouter), type(uint256).max);

        // Generate signature to one-time approve zap
        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermitFromFixedTestUser();

        uint256 _collShareBefore = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAddColl
        );

        vm.recordLogs();
        zapRouter.adjustCdpWithWstEth(
            _cdpIdToAddColl,
            0,
            0,
            false,
            bytes32(0),
            bytes32(0),
            _changeWstETH,
            false,
            pmPermit
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        _checkLogEvents(entries, _newIdx);

        uint256 _collShareAfter = cdpManager.getSyncedCdpCollShares(
            _cdpIdToAddColl
        );
        uint256 _collShareAdded = _changeWstETH;
        _checkCollAmtAgainstInput(
            _cdpIdToAddColl,
            (_collShareAfter - _collShareBefore),
            _collShareAdded
        );

        _checkZapStatusAfterOperation(user);

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    function _rangeInputCollAmount(
        uint256 _collAmt
    ) internal view returns (uint256) {
        if (_collAmt < MIN_FUZZ_COLL_SIZE) {
            return MIN_FUZZ_COLL_SIZE;
        } else if (_collAmt > MAX_FUZZ_COLL_SIZE) {
            return MAX_FUZZ_COLL_SIZE;
        } else {
            return _collAmt;
        }
    }

    function _checkCollAmtAgainstInput(
        bytes32 _cdpId,
        uint256 _coll,
        uint256 _input
    ) internal pure returns (bool) {
        bool _exactSame = _coll == _input ? true : false;
        uint256 _diff = (_coll > _input) ? (_coll - _input) : (_input - _coll);
        bool _diffInRange = _diff <= MAX_LOSS ? true : false;

        bool _finalCheck = false;
        if (_exactSame || _diffInRange) {
            _finalCheck = true;
        }
        if (!_exactSame) {
            console2.logString("diff for cdpId:");
            console2.logBytes32(_cdpId);
            console2.logString("colleteral:");
            console2.logUint(_coll);
            console2.logString("input amount:");
            console2.logUint(_input);
        }
        return _finalCheck;
    }

    function _checkLogEvents(
        Vm.Log[] memory _entries,
        uint256 _stIdx
    ) internal {
        for (uint256 i = 0; i < _entries.length; i++) {
            if (ZAP_EVENT_TARGET == _entries[i].topics[0]) {
                console2.logString("found ZapOperationEthVariant event:");
                console2.logUint(i);
                _checkLogEventData(
                    _entries[i].topics[1],
                    _stIdx,
                    _entries[i].data
                );
            }
        }
    }

    // ensure event got correct values
    function _checkLogEventData(
        bytes32 cdpId,
        uint256 _stIdx,
        bytes memory _evtData
    ) internal view {
        (
            bool _isCollateralIncrease,
            uint256 _collateralTokenDelta,
            uint256 _stEthDelta
        ) = abi.decode(_evtData, (bool, uint256, uint256));
        _checkCollAmtAgainstInput(
            cdpId,
            _stEthDelta,
            ((_collateralTokenDelta * _stIdx) / DEFAULT_INDEX)
        );
    }
}
