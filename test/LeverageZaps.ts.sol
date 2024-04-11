// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {EbtcZapRouter} from "../src/EbtcZapRouter.sol";
import {ZapRouterBaseInvariants} from "./ZapRouterBaseInvariants.sol";
import {IERC3156FlashLender} from "@ebtc/contracts/Interfaces/IERC3156FlashLender.sol";
import {IBorrowerOperations, IPositionManagers} from "@ebtc/contracts/LeverageMacroBase.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IEbtcZapRouter} from "../src/interface/IEbtcZapRouter.sol";
import {IEbtcLeverageZapRouter} from "../src/interface/IEbtcLeverageZapRouter.sol";
import {IEbtcZapRouterBase} from "../src/interface/IEbtcZapRouterBase.sol";

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
    /// @notice Collateral buffer used to account for slippage and fees
    /// 9995 = 0.05%
    uint256 internal constant COLLATERAL_BUFFER = 9995;

    function createLeveragedPosition() private returns (address user, bytes32 expectedCdpId) {
        user = vm.addr(userPrivateKey);

        _dealCollateralAndPrepForUse(user);

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        vm.startPrank(user);

        collateral.approve(address(leverageZapRouter), type(uint256).max);

        expectedCdpId = sortedCdps.toCdpId(user, block.number, sortedCdps.nextCdpNonce());

        uint256 _debt = 1e18;
        uint256 flAmount = _debtToCollateral(_debt);
        uint256 marginAmount = 5 ether;

        // Get before balances
        assertEq(
            _openTestCdp(_debt, flAmount, marginAmount, pmPermit),
            expectedCdpId,
            "CDP ID should match expected value"
        );

        vm.stopPrank();
    }

    function _openTestCdp(
        uint256 _debt, 
        uint256 _flAmount, 
        uint256 _marginAmount,
        IEbtcZapRouter.PositionManagerPermit memory pmPermit
    ) private returns (bytes32) {
        return leverageZapRouter.openCdp(
            _debt, // Debt amount
            bytes32(0),
            bytes32(0),
            _flAmount,
            _marginAmount, // Margin amount
            (_flAmount + _marginAmount) * COLLATERAL_BUFFER / SLIPPAGE_PRECISION,
            pmPermit,
            _getOpenCdpTradeData(_debt, _flAmount)
        );
    }

    function _getOpenCdpTradeData(uint256 _debt, uint256 expectedMinOut) 
        private returns (IEbtcLeverageZapRouter.TradeData memory) {
        return IEbtcLeverageZapRouter.TradeData({
            performSwapChecks: true,
            expectedMinOut: expectedMinOut,
            exchangeData: abi.encodeWithSelector(
                mockDex.swap.selector,
                address(eBTCToken),
                address(collateral),
                _debt // Debt amount
            )
        });
    }

    function test_ZapOpenCdp_WithStEth_LowLeverage() public {
        seedActivePool();

        (address user, bytes32 cdpId) = createLeveragedPosition();

        vm.startPrank(user);

        // Confirm Cdp opened for user
        bytes32[] memory userCdps = sortedCdps.getCdpsOf(user);
        assertEq(userCdps.length, 1, "User should have 1 cdp");

        // Confirm Zap has no cdps
        bytes32[] memory zapCdps = sortedCdps.getCdpsOf(address(leverageZapRouter));
        assertEq(zapCdps.length, 0, "Zap should not have a Cdp");

        // Confirm Zap has no coins
        assertEq(collateral.balanceOf(address(leverageZapRouter)), 0, "Zap should have no stETH balance");
        assertEq(collateral.sharesOf(address(leverageZapRouter)), 0, "Zap should have no stETH shares");
        assertEq(eBTCToken.balanceOf(address(leverageZapRouter)), 0, "Zap should have no eBTC");

        // Confirm PM approvals are cleared
        uint positionManagerApproval = uint256(
            borrowerOperations.getPositionManagerApproval(user, address(leverageZapRouter))
        );
        assertEq(
            positionManagerApproval,
            uint256(IPositionManagers.PositionManagerApproval.None),
            "Zap should have no PM approval after operation"
        );

        vm.stopPrank();

        _ensureSystemInvariants();
        _ensureZapInvariants();
    }

    function test_ZapCloseCdp_WithStEth_LowLeverage() public {
        seedActivePool();

        (address user, bytes32 cdpId) = createLeveragedPosition();

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        ICdpManagerData.Cdp memory cdpInfo = ICdpCdps(address(cdpManager)).Cdps(cdpId);
        uint256 flashFee = IERC3156FlashLender(address(borrowerOperations)).flashFee(
            address(eBTCToken),
            cdpInfo.debt
        );

        uint256 _maxSlippage = 10050; // 0.5% slippage

        assertEq(cdpManager.getCdpStatus(cdpId), uint256(ICdpManagerData.Status.active));
        
        uint256 flAmount = _debtToCollateral(cdpInfo.debt + flashFee);

        vm.startPrank(vm.addr(0x11111));
        vm.expectRevert("EbtcLeverageZapRouter: not owner for close!");
        leverageZapRouter.closeCdp(
            cdpId,
            pmPermit,
            (flAmount * _maxSlippage) / SLIPPAGE_PRECISION, 
            IEbtcLeverageZapRouter.TradeData({
                performSwapChecks: true,
                expectedMinOut: 0,
                exchangeData: abi.encodeWithSelector(
                    mockDex.swapExactOut.selector,
                    address(collateral),
                    address(eBTCToken),
                    cdpInfo.debt + flashFee
                )
            })
        );
        vm.stopPrank();

        vm.startPrank(user);

        leverageZapRouter.closeCdp(
            cdpId,
            pmPermit,
            (flAmount * _maxSlippage) / SLIPPAGE_PRECISION, 
            IEbtcLeverageZapRouter.TradeData({
                performSwapChecks: true,
                expectedMinOut: 0,
                exchangeData: abi.encodeWithSelector(
                    mockDex.swapExactOut.selector,
                    address(collateral),
                    address(eBTCToken),
                    cdpInfo.debt + flashFee
                )
            })
        );

        vm.stopPrank();

        assertEq(cdpManager.getCdpStatus(cdpId), uint256(ICdpManagerData.Status.closedByOwner));
    }

    function test_ZapCloseCdpWithDonation_WithStEth_LowLeverage() public {
        seedActivePool();

        (address user, bytes32 cdpId) = createLeveragedPosition();

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        vm.prank(user);
        collateral.transfer(address(leverageZapRouter), 1);

        vm.startPrank(user);

        ICdpManagerData.Cdp memory cdpInfo = ICdpCdps(address(cdpManager)).Cdps(cdpId);
        uint256 flashFee = IERC3156FlashLender(address(borrowerOperations)).flashFee(
            address(eBTCToken),
            cdpInfo.debt
        );
        
        uint256 _maxSlippage = 10050; // 0.5% slippage

        assertEq(cdpManager.getCdpStatus(cdpId), uint256(ICdpManagerData.Status.active));

        leverageZapRouter.closeCdp(
            cdpId,
            pmPermit,
            (_debtToCollateral(cdpInfo.debt + flashFee) * _maxSlippage) / SLIPPAGE_PRECISION, 
            IEbtcLeverageZapRouter.TradeData({
                performSwapChecks: true,
                expectedMinOut: 0,
                exchangeData: abi.encodeWithSelector(
                    mockDex.swapExactOut.selector,
                    address(collateral),
                    address(eBTCToken),
                    cdpInfo.debt + flashFee
                )
            })
        );

        assertEq(cdpManager.getCdpStatus(cdpId), uint256(ICdpManagerData.Status.closedByOwner));

        vm.stopPrank();
    }

    function test_adjustCdp_debtIncrease_stEth() public {
        seedActivePool();

        (address user, bytes32 cdpId) = createLeveragedPosition();

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        (uint256 debtBefore, uint256 collBefore) = cdpManager.getSyncedDebtAndCollShares(cdpId);
        uint256 icrBefore = cdpManager.getSyncedICR(cdpId, priceFeedMock.fetchPrice());

        uint256 debtChange = 0.1e18;
        uint256 collValue = _debtToCollateral(debtChange) * 9995 / 10000;
        uint256 stBalBefore = collateral.balanceOf(user);
        uint256 flAmount = _debtToCollateral(debtChange);

        vm.startPrank(vm.addr(0x11111));
        vm.expectRevert("EbtcLeverageZapRouter: not owner for adjust!");
        leverageZapRouter.adjustCdp(
            cdpId, 
            IEbtcLeverageZapRouter.AdjustCdpParams({
                flashLoanAmount: flAmount,
                debtChange: debtChange,
                isDebtIncrease: true,
                upperHint: bytes32(0),
                lowerHint: bytes32(0),
                stEthBalanceChange: collValue,
                isStEthBalanceIncrease: true,
                stEthMarginBalance: 0.5e18,
                isStEthMarginIncrease: true,
                useWstETHForDecrease: false
            }), 
            pmPermit, 
            IEbtcLeverageZapRouter.TradeData({
                performSwapChecks: false,
                expectedMinOut: 0,
                exchangeData: abi.encodeWithSelector(
                    mockDex.swap.selector,
                    address(eBTCToken),
                    address(collateral),
                    debtChange // Debt amount
                )
            })
        );
        vm.stopPrank();

        vm.startPrank(user);

        leverageZapRouter.adjustCdp(
            cdpId, 
            IEbtcLeverageZapRouter.AdjustCdpParams({
                flashLoanAmount: flAmount,
                debtChange: debtChange,
                isDebtIncrease: true,
                upperHint: bytes32(0),
                lowerHint: bytes32(0),
                stEthBalanceChange: collValue,
                isStEthBalanceIncrease: true,
                stEthMarginBalance: 0.5e18,
                isStEthMarginIncrease: true,
                useWstETHForDecrease: false
            }), 
            pmPermit, 
            IEbtcLeverageZapRouter.TradeData({
                performSwapChecks: false,
                expectedMinOut: 0,
                exchangeData: abi.encodeWithSelector(
                    mockDex.swap.selector,
                    address(eBTCToken),
                    address(collateral),
                    debtChange // Debt amount
                )
            })
        );

        (uint256 debtAfter, uint256 collAfter) = cdpManager.getSyncedDebtAndCollShares(cdpId);
        uint256 icrAfter = cdpManager.getSyncedICR(cdpId, priceFeedMock.fetchPrice());

        uint256 stBalAfter = collateral.balanceOf(user);

        console2.log("debtBefore  :", debtBefore);
        console2.log("debtAfter   :", debtAfter);
        console2.log("collBefore  :", collBefore);
        console2.log("collAfter   :", collAfter);    
        console2.log("icrBefore   :", icrBefore);
        console2.log("icrAfter    :", icrAfter);
        console2.log("stBalBefore :", stBalBefore);
        console2.log("stBalAfter  :", stBalAfter);

        vm.stopPrank();
    }

    function test_adjustCdp_debtDecrease_stEth() public {
        seedActivePool();

        (address user, bytes32 cdpId) = createLeveragedPosition();

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        vm.startPrank(user);

        (uint256 debtBefore, uint256 collBefore) = cdpManager.getSyncedDebtAndCollShares(cdpId);
        uint256 icrBefore = cdpManager.getSyncedICR(cdpId, priceFeedMock.fetchPrice());

        uint256 debtChange = 0.1e18;
        uint256 collValue = _debtToCollateral(debtChange) * 10003 / 10000 + 1;
        uint256 stBalBefore = collateral.balanceOf(user);

        leverageZapRouter.adjustCdp(
            cdpId, 
            IEbtcLeverageZapRouter.AdjustCdpParams({
                flashLoanAmount: debtChange,
                debtChange: debtChange,
                isDebtIncrease: false,
                upperHint: bytes32(0),
                lowerHint: bytes32(0),
                stEthBalanceChange: collValue,
                isStEthBalanceIncrease: false,
                stEthMarginBalance: 0.5e18,
                isStEthMarginIncrease: false,
                useWstETHForDecrease: false
            }), 
            pmPermit,
            IEbtcLeverageZapRouter.TradeData({
                performSwapChecks: false,
                expectedMinOut: 0,
                exchangeData: abi.encodeWithSelector(
                    mockDex.swap.selector,
                    address(collateral),
                    address(eBTCToken),
                    collValue // Debt amount
                )
            }) 
        );

        (uint256 debtAfter, uint256 collAfter) = cdpManager.getSyncedDebtAndCollShares(cdpId);
        uint256 icrAfter = cdpManager.getSyncedICR(cdpId, priceFeedMock.fetchPrice());

        uint256 stBalAfter = collateral.balanceOf(user);

        console2.log("debtBefore  :", debtBefore);
        console2.log("debtAfter   :", debtAfter);
        console2.log("collBefore  :", collBefore);
        console2.log("collAfter   :", collAfter);    
        console2.log("icrBefore   :", icrBefore);
        console2.log("icrAfter    :", icrAfter);
        console2.log("stBalBefore :", stBalBefore);
        console2.log("stBalAfter  :", stBalAfter);

        vm.stopPrank();
    }
}
