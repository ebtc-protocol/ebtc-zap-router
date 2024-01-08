// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {EbtcZapRouter} from "../src/EbtcZapRouter.sol";
import {ZapRouterBaseInvariants} from "./ZapRouterBaseInvariants.sol";
import {IERC3156FlashLender} from "@ebtc/contracts/Interfaces/IERC3156FlashLender.sol";
import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";
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

    function createLeveragedPosition() private returns (address, bytes32) {
        address user = vm.addr(userPrivateKey);

        _dealCollateralAndPrepForUse(user);

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        vm.startPrank(user);

        collateral.approve(address(leverageZapRouter), type(uint256).max);

        bytes32 expectedCdpId = sortedCdps.toCdpId(user, block.number, sortedCdps.nextCdpNonce());

        uint256 _debt = 1e18;
        uint256 flAmount = _debtToCollateral(_debt);
        uint256 marginAmount = 5 ether;

        // Get before balances
        assertEq(
            leverageZapRouter.openCdp(
                _debt, // Debt amount
                bytes32(0),
                bytes32(0),
                flAmount,
                marginAmount, // Margin amount
                (flAmount + marginAmount) * COLLATERAL_BUFFER / SLIPPAGE_PRECISION,
                pmPermit,
                abi.encodeWithSelector(
                    mockDex.swap.selector,
                    address(eBTCToken),
                    address(collateral),
                    _debt // Debt amount
                )
            ),
            expectedCdpId,
            "CDP ID should match expected value"
        );

        vm.stopPrank();

        return (user, expectedCdpId);
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

        vm.startPrank(user);

        ICdpManagerData.Cdp memory cdpInfo = ICdpCdps(address(cdpManager)).Cdps(cdpId);
        uint256 flashFee = IERC3156FlashLender(address(borrowerOperations)).flashFee(
            address(eBTCToken),
            cdpInfo.debt
        );

        uint256 _maxSlippage = 10050; // 0.5% slippage

        leverageZapRouter.closeCdp(
            cdpId,
            pmPermit,
            (_debtToCollateral(cdpInfo.debt + flashFee) * _maxSlippage) / SLIPPAGE_PRECISION, 
            abi.encodeWithSelector(
                mockDex.swapExactOut.selector,
                address(collateral),
                address(eBTCToken),
                cdpInfo.debt + flashFee
            )
        );

        vm.stopPrank();
    }

    function test_adjustCdp_debtIncrease_stEth() public {
        seedActivePool();

        (address user, bytes32 cdpId) = createLeveragedPosition();

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        vm.startPrank(user);

        (uint256 debtBefore, uint256 collBefore) = cdpManager.getSyncedDebtAndCollShares(cdpId);
        uint256 icrBefore = cdpManager.getSyncedICR(cdpId, priceFeedMock.fetchPrice());

        uint256 debtChange = 0.1e18;
        uint256 collValue = _debtToCollateral(debtChange) * 9995 / 10000;
        uint256 stBalBefore = collateral.balanceOf(user);

        leverageZapRouter.adjustCdp(
            cdpId, 
            IEbtcLeverageZapRouter.AdjustCdpParams({
                _flashLoanAmount: _debtToCollateral(debtChange),
                _debtChange: debtChange,
                _isDebtIncrease: true,
                _upperHint: bytes32(0),
                _lowerHint: bytes32(0),
                _stEthBalanceChange: collValue,
                _isStEthBalanceIncrease: true,
                _stEthMarginIncrease: 0,
                _useWstETHForDecrease: false
            }), 
            pmPermit, 
            abi.encodeWithSelector(
                mockDex.swap.selector,
                address(eBTCToken),
                address(collateral),
                debtChange // Debt amount
            )
        );

        (uint256 debtAfter, uint256 collAfter) = cdpManager.getSyncedDebtAndCollShares(cdpId);
        uint256 icrAfter = cdpManager.getSyncedICR(cdpId, priceFeedMock.fetchPrice());

        uint256 stBalAfter = collateral.balanceOf(user);

        console2.log("debtBefore", debtBefore);
        console2.log("debtAfter", debtAfter);
        console2.log("collBefore", collBefore);
        console2.log("collAfter", collAfter);
        console2.log("icrBefore", icrBefore);
        console2.log("icrAfter", icrAfter);
        console2.log("stBalBefore", stBalBefore);
        console2.log("stBalAfter", stBalAfter);

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
        uint256 collValue = _debtToCollateral(debtChange) * 10005 / 10000;
        uint256 stBalBefore = collateral.balanceOf(user);

        leverageZapRouter.adjustCdp(
            cdpId, 
            IEbtcLeverageZapRouter.AdjustCdpParams({
                _flashLoanAmount: debtChange,
                _debtChange: debtChange,
                _isDebtIncrease: false,
                _upperHint: bytes32(0),
                _lowerHint: bytes32(0),
                _stEthBalanceChange: collValue,
                _isStEthBalanceIncrease: false,
                _stEthMarginIncrease: 0,
                _useWstETHForDecrease: false
            }), 
            pmPermit, 
            abi.encodeWithSelector(
                mockDex.swap.selector,
                address(collateral),
                address(eBTCToken),
                collValue // Debt amount
            )
        );

        (uint256 debtAfter, uint256 collAfter) = cdpManager.getSyncedDebtAndCollShares(cdpId);
        uint256 icrAfter = cdpManager.getSyncedICR(cdpId, priceFeedMock.fetchPrice());

        uint256 stBalAfter = collateral.balanceOf(user);

        console2.log("debtBefore", debtBefore);
        console2.log("debtAfter", debtAfter);
        console2.log("collBefore", collBefore);
        console2.log("collAfter", collAfter);    
        console2.log("icrBefore", icrBefore);
        console2.log("icrAfter", icrAfter);
        console2.log("stBalBefore", stBalBefore);
        console2.log("stBalAfter", stBalAfter);

        vm.stopPrank();
    }
}
