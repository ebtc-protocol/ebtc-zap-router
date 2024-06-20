// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {EbtcZapRouter} from "../src/EbtcZapRouter.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {ZapRouterBaseInvariants} from "./ZapRouterBaseInvariants.sol";
import {IERC3156FlashLender} from "@ebtc/contracts/Interfaces/IERC3156FlashLender.sol";
import {IBorrowerOperations, IPositionManagers} from "@ebtc/contracts/LeverageMacroBase.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IEbtcZapRouter} from "../src/interface/IEbtcZapRouter.sol";
import {IEbtcLeverageZapRouter} from "../src/interface/IEbtcLeverageZapRouter.sol";
import {IEbtcZapRouterBase} from "../src/interface/IEbtcZapRouterBase.sol";
import {IWstETH} from "../src/interface/IWstETH.sol";
import {IWrappedETH} from "../src/interface/IWrappedETH.sol";

interface ICdpCdps {
    function Cdps(bytes32) external view returns (ICdpManagerData.Cdp memory);
}

contract LeverageZaps is ZapRouterBaseInvariants {
    function setUp() public override {
        super.setUp();
    }

    function seedActivePool() private returns (address) {
        address whale = vm.addr(0xabc456);
        _dealCollateralAndPrepForUse(whale);

        vm.startPrank(whale);
        collateral.approve(address(borrowerOperations), type(uint256).max);

        // Seed AP
        borrowerOperations.openCdp(2e18, bytes32(0), bytes32(0), 600 ether);

        // Seed mock dex
        eBTCToken.transfer(address(mockDex), 2e18);

        vm.stopPrank();

        // Give stETH to mock dex
        mockDex.setPrice(priceFeedMock.fetchPrice());
        vm.deal(address(mockDex), type(uint96).max);
        vm.prank(address(mockDex));
        collateral.deposit{value: 10000 ether}();
    }

    function createPermit(
        address user
    ) private returns (IEbtcZapRouter.PositionManagerPermit memory pmPermit) {
        uint _deadline = (block.timestamp + deadline);
        IPositionManagers.PositionManagerApproval _approval = IPositionManagers
            .PositionManagerApproval
            .OneTime;

        vm.startPrank(user);

        // Generate signature to one-time approve zap
        bytes32 digest = _generatePermitSignature(user, address(leverageZapRouter), _approval, _deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        pmPermit = IEbtcZapRouterBase.PositionManagerPermit(_deadline, v, r, s);

        vm.stopPrank();
    }

    function _debtToCollateral(uint256 _debt) public returns (uint256) {
        uint256 price = priceFeedMock.fetchPrice();
        return (_debt * 1e18) / price;
    }

    uint256 internal constant SLIPPAGE_PRECISION = 1e4;
    /// @notice Collateral buffer used to account for slippage and fees (zap fee included)
    /// 9970 = 0.30%
    uint256 internal constant COLLATERAL_BUFFER = 9970;

    function createLeveragedPosition(MarginType marginType) private returns (address user, bytes32 expectedCdpId) {
        user = vm.addr(userPrivateKey);

        uint256 _debt = 1e18;
        uint256 flAmount = _debtToCollateral(_debt);
        uint256 marginAmount = 5 ether;

        if (marginType == MarginType.stETH) {
            _dealCollateralAndPrepForUse(user);
            vm.prank(user);
            collateral.approve(address(leverageZapRouter), type(uint256).max);
        } else if (marginType == MarginType.wstETH) {
            _dealCollateralAndPrepForUse(user);
            vm.startPrank(user);
            collateral.approve(address(testWstEth), type(uint256).max);
            IWstETH(testWstEth).wrap(collateral.balanceOf(user));
            IERC20(testWstEth).approve(address(leverageZapRouter), type(uint256).max);
            marginAmount = IWstETH(testWstEth).getWstETHByStETH(marginAmount);
            vm.stopPrank();
        } else if (marginType == MarginType.ETH) {
            vm.deal(user, type(uint96).max);
        } else if (marginType == MarginType.WETH) {
            vm.deal(user, type(uint96).max);
            vm.startPrank(user);
            IWrappedETH(testWeth).deposit{value: marginAmount}();
            IERC20(testWeth).approve(address(leverageZapRouter), type(uint256).max);
            vm.stopPrank();
        } else {
            revert();
        }

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        vm.startPrank(user);

        expectedCdpId = sortedCdps.toCdpId(user, block.number, sortedCdps.nextCdpNonce());

        // Get before balances
        assertEq(
            _openTestCdp(marginType, _debt, flAmount, marginAmount, pmPermit),
            expectedCdpId,
            "CDP ID should match expected value"
        );

        vm.stopPrank();
    }

    function _openTestCdp(
        MarginType marginType,
        uint256 _debt, 
        uint256 _flAmount, 
        uint256 _marginAmount,
        IEbtcZapRouter.PositionManagerPermit memory pmPermit
    ) private returns (bytes32) {
        if (marginType == MarginType.stETH) {
            return leverageZapRouter.openCdp(
                _debt, // Debt amount
                bytes32(0),
                bytes32(0),
                _flAmount,
                _marginAmount, // Margin amount
                (_flAmount + _marginAmount) * COLLATERAL_BUFFER / SLIPPAGE_PRECISION,
                abi.encode(pmPermit),
                _getOpenCdpTradeData(_debt, _flAmount)
            );
        } else if (marginType == MarginType.wstETH) {
            return leverageZapRouter.openCdpWithWstEth(
                _debt, // Debt amount
                bytes32(0),
                bytes32(0),
                _flAmount,
                _marginAmount, // Margin amount
                (_flAmount + IWstETH(testWstEth).getStETHByWstETH(_marginAmount)) * COLLATERAL_BUFFER / SLIPPAGE_PRECISION,
                abi.encode(pmPermit),
                _getOpenCdpTradeData(_debt, _flAmount)
            );
        } else if (marginType == MarginType.ETH) {
            return leverageZapRouter.openCdpWithEth{value: _marginAmount}(
                _debt, // Debt amount
                bytes32(0),
                bytes32(0),
                _flAmount,
                _marginAmount, // Margin amount
                (_flAmount + _marginAmount) * COLLATERAL_BUFFER / SLIPPAGE_PRECISION,
                abi.encode(pmPermit),
                _getOpenCdpTradeData(_debt, _flAmount)
            );
        } else if (marginType == MarginType.WETH) {
            return leverageZapRouter.openCdpWithWrappedEth(
                _debt, // Debt amount
                bytes32(0),
                bytes32(0),
                _flAmount,
                _marginAmount, // Margin amount
                (_flAmount + _marginAmount) * COLLATERAL_BUFFER / SLIPPAGE_PRECISION,
                abi.encode(pmPermit),
                _getOpenCdpTradeData(_debt, _flAmount)
            );
        } else {
            revert();
        }
    }

    function _getOpenCdpTradeData(uint256 _debt, uint256 expectedMinOut) 
        private returns (IEbtcLeverageZapRouter.TradeData memory) {
        _debt = _debt - (_debt * defaultZapFee / 10000);
        expectedMinOut = expectedMinOut - (expectedMinOut * defaultZapFee / 10000);
        return IEbtcLeverageZapRouter.TradeData({
            performSwapChecks: true,
            expectedMinOut: expectedMinOut,
            exchangeData: abi.encodeWithSelector(
                mockDex.swap.selector,
                address(eBTCToken),
                address(collateral),
                _debt // Debt amount
            ),
            approvalAmount: _debt,
            collValidationBufferBPS: 10500 // 5%
        });
    }

    function test_ZapOpenCdp_WithStEth_LowLeverage() public {
        seedActivePool();

        _before();
        (address user, bytes32 cdpId) = createLeveragedPosition(MarginType.stETH);
        _after();

        // Confirm Cdp opened for user
        bytes32[] memory userCdps = sortedCdps.getCdpsOf(user);
        assertEq(userCdps.length, 1, "User should have 1 cdp");

        // Test zap fee
        assertEq(eBTCToken.balanceOf(testFeeReceiver), 1e18 * defaultZapFee / 10000); 

        _checkZapStatusAfterOperation(user);
        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    function test_ZapOpenCdp_WithWstEth_LowLeverage() public {
        seedActivePool();

        _before();
        (address user, bytes32 cdpId) = createLeveragedPosition(MarginType.wstETH);
        _after();

        // Confirm Cdp opened for user
        bytes32[] memory userCdps = sortedCdps.getCdpsOf(user);
        assertEq(userCdps.length, 1, "User should have 1 cdp");

        // Test zap fee
        assertEq(eBTCToken.balanceOf(testFeeReceiver), 1e18 * defaultZapFee / 10000); 

        _checkZapStatusAfterOperation(user);
        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    function test_ZapOpenCdp_WithEth_LowLeverage() public {
        seedActivePool();

        _before();
        (address user, bytes32 cdpId) = createLeveragedPosition(MarginType.ETH);
        _after();

        // Confirm Cdp opened for user
        bytes32[] memory userCdps = sortedCdps.getCdpsOf(user);
        assertEq(userCdps.length, 1, "User should have 1 cdp");

        // Test zap fee
        assertEq(eBTCToken.balanceOf(testFeeReceiver), 1e18 * defaultZapFee / 10000); 

        _checkZapStatusAfterOperation(user);
        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    function test_ZapOpenCdp_WithWrappedEth_LowLeverage() public {
        seedActivePool();

        _before();
        (address user, bytes32 cdpId) = createLeveragedPosition(MarginType.WETH);
        _after();

        // Confirm Cdp opened for user
        bytes32[] memory userCdps = sortedCdps.getCdpsOf(user);
        assertEq(userCdps.length, 1, "User should have 1 cdp");

        // Test zap fee
        assertEq(eBTCToken.balanceOf(testFeeReceiver), 1e18 * defaultZapFee / 10000); 

        _checkZapStatusAfterOperation(user);
        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    function test_ZapCloseCdp_WithStEth_LowLeverage() public {
        seedActivePool();

        (address user, bytes32 cdpId) = createLeveragedPosition(MarginType.stETH);

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        (uint256 debt, uint256 collShares) = cdpManager.getSyncedDebtAndCollShares(cdpId);

        assertEq(cdpManager.getCdpStatus(cdpId), uint256(ICdpManagerData.Status.active));

        uint256 stEthAmount = collateral.getPooledEthByShares(collShares);
        IEbtcLeverageZapRouter.TradeData memory tradeData = _getExactOutCollateralToDebtTradeData(
            debt, 
            stEthAmount * COLLATERAL_BUFFER / SLIPPAGE_PRECISION
        );
        
        vm.startPrank(vm.addr(0x11111));
        vm.expectRevert("EbtcLeverageZapRouter: not owner for close!");
        leverageZapRouter.closeCdp(
            cdpId,
            abi.encode(pmPermit),
            tradeData
        );
        vm.stopPrank();

        vm.startPrank(user);

        _before();
        leverageZapRouter.closeCdp(
            cdpId,
            abi.encode(pmPermit),
            tradeData
        );
        _after();

        vm.stopPrank();

        assertEq(cdpManager.getCdpStatus(cdpId), uint256(ICdpManagerData.Status.closedByOwner));

        _checkZapStatusAfterOperation(user);
    }

    function test_ZapCloseCdp_WithWstEth_LowLeverage() public {
        seedActivePool();

        (address user, bytes32 cdpId) = createLeveragedPosition(MarginType.stETH);

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        vm.prank(user);
        collateral.transfer(address(leverageZapRouter), 1);

        vm.startPrank(user);

        (uint256 debt, uint256 collShares) = cdpManager.getSyncedDebtAndCollShares(cdpId);

        assertEq(cdpManager.getCdpStatus(cdpId), uint256(ICdpManagerData.Status.active));
        uint256 _stETHValBefore = IERC20(address(testWstEth)).balanceOf(user);

        _before();
        leverageZapRouter.closeCdpForWstETH(
            cdpId,
            abi.encode(pmPermit),
            _getExactOutCollateralToDebtTradeData(
                debt, 
                collateral.getPooledEthByShares(collShares) * COLLATERAL_BUFFER / SLIPPAGE_PRECISION
            )
        );
        _after();

        assertEq(cdpManager.getCdpStatus(cdpId), uint256(ICdpManagerData.Status.closedByOwner));

        uint256 _stETHValAfter = IERC20(address(testWstEth)).balanceOf(user);
        assertEq(_stETHValAfter - _stETHValBefore, 4940573505654281098);

        vm.stopPrank();

        _checkZapStatusAfterOperation(user);
    }

    function test_ZapCloseCdpWithDonation_WithStEth_LowLeverage() public {
        seedActivePool();

        (address user, bytes32 cdpId) = createLeveragedPosition(MarginType.stETH);

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        vm.prank(user);
        collateral.transfer(address(leverageZapRouter), 1);

        vm.startPrank(user);

        (uint256 debt, uint256 collShares) = cdpManager.getSyncedDebtAndCollShares(cdpId);
        
        assertEq(cdpManager.getCdpStatus(cdpId), uint256(ICdpManagerData.Status.active));

        _before();
        leverageZapRouter.closeCdp(
            cdpId,
            abi.encode(pmPermit),
            _getExactOutCollateralToDebtTradeData(
                debt, 
                collateral.getPooledEthByShares(collShares) * COLLATERAL_BUFFER / SLIPPAGE_PRECISION
            )
        );
        _after();

        assertEq(cdpManager.getCdpStatus(cdpId), uint256(ICdpManagerData.Status.closedByOwner));

        vm.stopPrank();

        _checkZapStatusAfterOperation(user);
    }

    function _getAdjustCdpParams(
        uint256 _flAmount, 
        int256 _debtChange,
        int256 _collValue,
        int256 _marginBalance,
        bool _useWstETHForDecrease
    ) private view returns (IEbtcLeverageZapRouter.AdjustCdpParams memory) {
        return IEbtcLeverageZapRouter.AdjustCdpParams({
            flashLoanAmount: _flAmount,
            debtChange: _debtChange < 0 ? uint256(-_debtChange) : uint256(_debtChange),
            isDebtIncrease: _debtChange > 0,
            upperHint: bytes32(0),
            lowerHint: bytes32(0),
            stEthBalanceChange: _collValue < 0 ? uint256(-_collValue) : uint256(_collValue),
            isStEthBalanceIncrease: _collValue > 0,
            stEthMarginBalance: _marginBalance < 0 ? uint256(-_marginBalance) : uint256(_marginBalance),
            isStEthMarginIncrease: _marginBalance > 0,
            useWstETHForDecrease: _useWstETHForDecrease
        });
    }

    function _getExactOutCollateralToDebtTradeData(
        uint256 _debtAmount,
        uint256 _collAmount
    ) private view returns (IEbtcLeverageZapRouter.TradeData memory) {
        uint256 flashFee = IERC3156FlashLender(address(borrowerOperations)).flashFee(
            address(eBTCToken),
            _debtAmount
        );

        return IEbtcLeverageZapRouter.TradeData({
            performSwapChecks: false,
            expectedMinOut: 0,
            exchangeData: abi.encodeWithSelector(
                mockDex.swapExactOut.selector,
                address(collateral),
                address(eBTCToken),
                _debtAmount + flashFee
            ),
            approvalAmount: _collAmount,
            collValidationBufferBPS: 10500 // 5%
        });
    }

    function _getExactInDebtToCollateralTradeData(
        uint256 _amount
    ) private view returns (IEbtcLeverageZapRouter.TradeData memory) {
        _amount = _amount - (_amount * defaultZapFee / 10000);
        return IEbtcLeverageZapRouter.TradeData({
            performSwapChecks: false,
            expectedMinOut: 0,
            exchangeData: abi.encodeWithSelector(
                mockDex.swap.selector,
                address(eBTCToken),
                address(collateral),
                _amount // Debt amount
            ),
            approvalAmount: _amount,
            collValidationBufferBPS: 10500 // 5%
        });
    }

   function _getExactInCollateralToDebtTradeData(
        uint256 _amount
    ) private view returns (IEbtcLeverageZapRouter.TradeData memory) {
        return IEbtcLeverageZapRouter.TradeData({
            performSwapChecks: false,
            expectedMinOut: 0,
            exchangeData: abi.encodeWithSelector(
                mockDex.swap.selector,
                address(collateral),
                address(eBTCToken),
                _amount // Debt amount
            ),
            approvalAmount: _amount,
            collValidationBufferBPS: 10500 // 5%
        });
    }

    function test_adjustCdp_debtIncrease_stEth() public {
        seedActivePool();

        (address user, bytes32 cdpId) = createLeveragedPosition(MarginType.stETH);

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        uint256 debtChange = 2e18;
        uint256 marginIncrease = 0.5e18;
        uint256 collValue = _debtToCollateral(debtChange) * COLLATERAL_BUFFER / 10000;
        uint256 flAmount = _debtToCollateral(debtChange);

        vm.startPrank(vm.addr(0x11111));
        vm.expectRevert("EbtcLeverageZapRouter: not owner for adjust!");
        leverageZapRouter.adjustCdp(
            cdpId, 
            _getAdjustCdpParams(flAmount, int256(debtChange), int256(collValue), 0, false), 
            abi.encode(pmPermit), 
            _getExactInDebtToCollateralTradeData(debtChange)
        );
        vm.stopPrank();

        _before();
        vm.startPrank(user);
        leverageZapRouter.adjustCdp(
            cdpId, 
            _getAdjustCdpParams(flAmount, int256(debtChange), int256(collValue), int256(marginIncrease), false),
            abi.encode(pmPermit), 
            _getExactInDebtToCollateralTradeData(debtChange)
        );
        vm.stopPrank();
        _after();

        // Test zap fee
        assertEq(eBTCToken.balanceOf(testFeeReceiver), (1e18 + debtChange) * defaultZapFee / 10000); 

        _checkZapStatusAfterOperation(user);
    }

    function test_adjustCdp_debtDecrease_stEth() public {
        seedActivePool();

        (address user, bytes32 cdpId) = createLeveragedPosition(MarginType.stETH);

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        uint256 debtChange = 0.8e18;
        uint256 marginBalance = 0.5e18;
        uint256 collValue = _debtToCollateral(debtChange) * 10004 / 10000;

        _before();
        vm.startPrank(user);
        leverageZapRouter.adjustCdp(
            cdpId, 
            _getAdjustCdpParams(debtChange, -int256(debtChange), -int256(collValue), -int256(marginBalance), false), 
            abi.encode(pmPermit),
            _getExactInCollateralToDebtTradeData(collValue)
        );
        vm.stopPrank();
        _after();

        // Test zap fee (no fee if debt decrease)
        assertEq(eBTCToken.balanceOf(testFeeReceiver), 1e18 * defaultZapFee / 10000); 

        _checkZapStatusAfterOperation(user);
    }
}
