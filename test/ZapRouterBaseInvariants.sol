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
import {WETH9} from "@ebtc/contracts/TestContracts/WETH9.sol";
import {IStETH} from "../src/interface/IStETH.sol";
import {IEbtcZapRouter} from "../src/interface/IEbtcZapRouter.sol";
import {WstETH} from "../src/testContracts/WstETH.sol";
import {IWstETH} from "../src/interface/IWstETH.sol";

contract ZapRouterBaseInvariants is
    eBTCBaseInvariants,
    ZapRouterBaseStorageVariables
{
    struct ZapRouterState {
        uint256 stEthBalance;
        uint256 collShares;
    }

    uint256 public constant FIXED_COLL_SIZE = 30 ether;
    uint256 public constant MAX_COLL_ROUNDING_ERROR = 2;
    address internal TEST_FIXED_USER;
    ZapRouterState internal stateBefore;
    ZapRouterState internal stateAfter;

    function setUp() public virtual override {
        super.setUp();
        testWeth = address(new WETH9());
        testWstEth = address(new WstETH(address(collateral)));
        zapRouter = new EbtcZapRouter(
            IERC20(testWstEth),
            IERC20(testWeth),
            IStETH(address(collateral)),
            IERC20(address(eBTCToken)),
            IBorrowerOperations(address(borrowerOperations)),
            ICdpManager(address(cdpManager)),
            defaultGovernance
        );
        TEST_FIXED_USER = _createUserFromPrivateKey(userPrivateKey);
    }

    function _before() internal {
        stateBefore.collShares = collateral.sharesOf(address(zapRouter));
        stateBefore.stEthBalance = collateral.balanceOf(address(zapRouter));
    }

    function _after() internal {
        stateAfter.collShares = collateral.sharesOf(address(zapRouter));
        stateAfter.stEthBalance = collateral.balanceOf(address(zapRouter));
    }

    function _ensureZapInvariants() internal {
        // TODO
    }

    function _checkZapStatusAfterOperation(address _user) internal {
        // Confirm Zap has no cdps
        bytes32[] memory zapCdps = sortedCdps.getCdpsOf(address(zapRouter));
        assertEq(zapCdps.length, 0, "Zap should not have a Cdp");

        // Confirm Zap has no coins
        assertLe(
            stateAfter.stEthBalance - stateBefore.stEthBalance,
            MAX_COLL_ROUNDING_ERROR,
            "Zap should have no stETH balance"
        );
        assertLe(
            stateAfter.collShares - stateBefore.collShares,
            MAX_COLL_ROUNDING_ERROR,
            "Zap should have no stETH shares"
        );
        assertEq(
            eBTCToken.balanceOf(address(zapRouter)),
            0,
            "Zap should have no eBTC"
        );
        assertEq(address(zapRouter).balance, 0, "Zap should have no raw ETH");
        assertEq(
            IERC20(testWeth).balanceOf(address(zapRouter)),
            0,
            "Zap should have no wrapped ETH"
        );
        assertEq(
            IERC20(testWstEth).balanceOf(address(zapRouter)),
            0,
            "Zap should have no wrapped stETH"
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

    function _dealWrappedEtherForUser(
        address _user
    ) internal returns (uint256) {
        return
            _dealWrappedEtherForUserWithAmount(
                _user,
                FIXED_COLL_SIZE + 0.2 ether
            );
    }

    function _dealWrappedEtherForUserWithAmount(
        address _user,
        uint256 _amt
    ) internal returns (uint256) {
        require(_amt > 0, "WETH increase expected should > 0!");
        uint256 _balBefore = IERC20(testWeth).balanceOf(_user);
        vm.prank(_user);
        WETH9(testWeth).deposit{value: _amt}();
        uint256 _newWETHBal = IERC20(testWeth).balanceOf(_user) - _balBefore;
        require(
            _newWETHBal > 0,
            "WETH balance should increase as expected at this moment"
        );
        return _newWETHBal;
    }

    function _dealWrappedStETHForUser(
        address _user
    ) internal returns (uint256) {
        return
            _dealWrappedStETHForUserWithAmount(
                _user,
                IWstETH(testWstEth).getWstETHByStETH(
                    FIXED_COLL_SIZE + 0.2 ether
                )
            );
    }

    function _dealWrappedStETHForUserWithAmount(
        address _user,
        uint256 _amt
    ) internal returns (uint256) {
        require(_amt > 0, "WstETH increase expected should > 0!");
        uint256 _stETHRequired = IWstETH(testWstEth).getStETHByWstETH(_amt);

        vm.startPrank(_user);
        collateral.deposit{value: _stETHRequired * 2}();
        collateral.approve(testWstEth, type(uint256).max);
        uint256 _newWstETHBal = IWstETH(testWstEth).wrap(_stETHRequired);
        require(
            _newWstETHBal > 0,
            "WstETH balance should increase as expected at this moment"
        );
        vm.stopPrank();

        return _newWstETHBal;
    }
}
