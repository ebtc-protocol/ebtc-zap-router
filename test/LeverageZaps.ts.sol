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

    function createLeveragedPosition() private returns (address, bytes32) {
        address user = vm.addr(userPrivateKey);

        _dealCollateralAndPrepForUse(user);

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = createPermit(user);

        vm.startPrank(user);

        collateral.approve(address(leverageZapRouter), type(uint256).max);

        bytes32 expectedCdpId = sortedCdps.toCdpId(user, block.number, sortedCdps.nextCdpNonce());

        // Get before balances
        assertEq(
            leverageZapRouter.openCdp(
                1e18, // Debt amount
                bytes32(0),
                bytes32(0),
                5 ether, // Margin amount
                pmPermit,
                abi.encodeWithSelector(
                    mockDex.swap.selector,
                    address(eBTCToken),
                    address(collateral),
                    1e18 // Debt amount
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

        leverageZapRouter.closeCdp(
            cdpId,
            pmPermit,
            10050, // 0.5% slippage
            abi.encodeWithSelector(
                mockDex.swapExactOut.selector,
                address(collateral),
                address(eBTCToken),
                cdpInfo.debt + flashFee
            )
        );

        vm.stopPrank();
    }
}
