// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {EbtcZapRouter} from "../src/EbtcZapRouter.sol";
import {ZapRouterBaseStorageVariables} from "../src/invariants/ZapRouterBaseStorageVariables.sol";
import {eBTCBaseInvariants} from "@ebtc/foundry_test/BaseInvariants.sol";
import {ICdpManager} from "@ebtc/contracts/interfaces/ICdpManager.sol";
import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {IStETH} from "../src/interface/IStETH.sol";
import {IEbtcZapRouter} from "../src/interface/IEbtcZapRouter.sol";

contract ZapRouterBaseInvariants is
    eBTCBaseInvariants,
    ZapRouterBaseStorageVariables
{
    address internal TEST_FIXED_USER;

    function setUp() public virtual override {
        super.setUp();
        zapRouter = new EbtcZapRouter(
            IStETH(address(collateral)),
            IERC20(address(eBTCToken)),
            IBorrowerOperations(address(borrowerOperations)),
            ICdpManager(address(cdpManager))
        );
        TEST_FIXED_USER = _createUserFromPrivateKey(userPrivateKey);
    }

    function _ensureZapInvariants() internal {
        // TODO
    }

    function _checkZapStatusAfterOperation(address _user) internal {
        // Confirm Zap has no cdps
        bytes32[] memory zapCdps = sortedCdps.getCdpsOf(address(zapRouter));
        assertEq(zapCdps.length, 0, "Zap should not have a Cdp");

        // Confirm Zap has no coins
        assertEq(
            collateral.balanceOf(address(zapRouter)),
            0,
            "Zap should have no stETH balance"
        );
        assertEq(
            collateral.sharesOf(address(zapRouter)),
            0,
            "Zap should have no stETH shares"
        );
        assertEq(
            eBTCToken.balanceOf(address(zapRouter)),
            0,
            "Zap should have no eBTC"
        );

        // Confirm PM approvals are cleared
        uint positionManagerApproval = uint256(
            borrowerOperations.getPositionManagerApproval(
                _user,
                address(zapRouter)
            )
        );
        assertEq(
            positionManagerApproval,
            uint256(IPositionManagers.PositionManagerApproval.None),
            "Zap should have no PM approval after operation"
        );
    }

    //// utility functions

    function _createUserFromPrivateKey(
        uint256 _privateKey
    ) internal returns (address user) {
        user = vm.addr(_privateKey);
    }

    function _generatePermitSignature(
        address _signer,
        address _positionManager,
        IPositionManagers.PositionManagerApproval _approval,
        uint _deadline
    ) internal returns (bytes32) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                borrowerOperations.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        borrowerOperations.permitTypeHash(),
                        _signer,
                        _positionManager,
                        _approval,
                        borrowerOperations.nonces(_signer),
                        _deadline
                    )
                )
            )
        );
        return digest;
    }

    function _generateOneTimePermitFromFixedTestUser()
        internal
        returns (IEbtcZapRouter.PositionManagerPermit memory)
    {
        uint _deadline = (block.timestamp + deadline);
        IPositionManagers.PositionManagerApproval _approval = IPositionManagers
            .PositionManagerApproval
            .OneTime;

        // Generate signature to one-time approve zap
        bytes32 digest = _generatePermitSignature(
            TEST_FIXED_USER,
            address(zapRouter),
            _approval,
            _deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = IEbtcZapRouter
            .PositionManagerPermit(_deadline, v, r, s);
        return pmPermit;
    }

    function _dealRawEtherForUser(address _user) internal {
        vm.deal(_user, type(uint96).max);
    }
}
