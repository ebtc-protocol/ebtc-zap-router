// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/Hevm.sol";
import {TargetContractSetup} from "@ebtc/contracts/TestContracts/invariants/TargetContractSetup.sol";
import {CollateralTokenTester} from "@ebtc/contracts/TestContracts/CollateralTokenTester.sol";
import {Mock1Inch} from "@ebtc/contracts/TestContracts/Mock1Inch.sol";
import {ICdpManager} from "@ebtc/contracts/interfaces/ICdpManager.sol";
import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {WETH9} from "@ebtc/contracts/TestContracts/WETH9.sol";
import {IStETH} from "../../src/interface/IStETH.sol";
import {ZapRouterProperties} from "../../src/invariants/ZapRouterProperties.sol";
import {EbtcZapRouter} from "../../src/EbtcZapRouter.sol";
import {EbtcLeverageZapRouter} from "../../src/EbtcLeverageZapRouter.sol";
import {ZapRouterActor} from "../../src/invariants/ZapRouterActor.sol";
import {IEbtcZapRouter} from "../../src/interface/IEbtcZapRouter.sol";
import {IEbtcLeverageZapRouter} from "../../src/interface/IEbtcLeverageZapRouter.sol";
import {IEbtcZapRouterBase} from "../../src/interface/IEbtcZapRouterBase.sol";
import {WstETH} from "../../src/testContracts/WstETH.sol";

abstract contract TargetFunctionsBase is TargetContractSetup, ZapRouterProperties {
    modifier setup() virtual {
        zapSender = msg.sender;
        zapActor = zapActors[msg.sender];
        zapActorKey = zapActorKeys[msg.sender];
        _;
    }

    function setUpActors() internal {
        bool success;
        address[] memory tokens = new address[](4);
        tokens[0] = address(eBTCToken);
        tokens[1] = address(collateral);
        tokens[2] = testWeth;
        tokens[3] = testWstEth;
        address[] memory addresses = new address[](3);
        addresses[0] = hevm.addr(USER1_PK);
        addresses[1] = hevm.addr(USER2_PK);
        addresses[2] = hevm.addr(USER3_PK);
        zapActorKeys[addresses[0]] = USER1_PK;
        zapActorKeys[addresses[1]] = USER2_PK;
        zapActorKeys[addresses[2]] = USER3_PK;
        for (uint i = 0; i < NUMBER_OF_ACTORS; i++) {
            zapActors[addresses[i]] = new ZapRouterActor(
                tokens,
                address(zapRouter),
                address(leverageZapRouter),
                addresses[i]
            );
        }
    }

    function _dealETH(ZapRouterActor actor) internal {
        (bool success, ) = address(actor).call{value: INITIAL_ETH_BALANCE}("");
        assert(success);
    }

    function _dealWETH(ZapRouterActor actor) internal {
        _dealETH(actor);
        (bool success, ) = actor.proxy(
            address(testWeth),
            abi.encodeWithSelector(WETH9.deposit.selector, ""),
            INITIAL_ETH_BALANCE,
            false
        );
        assert(success);
        (success, ) = actor.proxy(
            address(testWeth),
            abi.encodeWithSelector(
                WETH9.transfer.selector,
                actor.sender(),
                INITIAL_ETH_BALANCE
            ),
            false
        );
        assert(success);
    }

    function _dealCollateral(ZapRouterActor actor, uint256 amount) internal {
        _dealETH(actor);
        (bool success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(CollateralTokenTester.deposit.selector, ""),
            amount,
            false
        );
        assert(success);
    }

    function _dealWrappedCollateral(ZapRouterActor actor) internal {
        _dealETH(actor);
        (bool success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(CollateralTokenTester.deposit.selector, ""),
            INITIAL_COLL_BALANCE,
            false
        );
        assert(success);
        (success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(
                CollateralTokenTester.approve.selector,
                address(testWstEth),
                INITIAL_COLL_BALANCE
            ),
            false
        );
        assert(success);
        uint256 amountBefore = IERC20(testWstEth).balanceOf(address(actor));
        (success, ) = actor.proxy(
            testWstEth,
            abi.encodeWithSelector(WstETH.wrap.selector, INITIAL_COLL_BALANCE),
            false
        );
        assert(success);
        uint256 amountAfter = IERC20(testWstEth).balanceOf(address(actor));
        (success, ) = actor.proxy(
            testWstEth,
            abi.encodeWithSelector(
                IERC20.transfer.selector,
                actor.sender(),
                amountAfter - amountBefore
            ),
            false
        );
        assert(success);
    }

    function _checkApproval(address _user) internal {
        uint positionManagerApproval = uint256(
            borrowerOperations.getPositionManagerApproval(
                _user,
                address(zapRouter)
            )
        );

        t(
            positionManagerApproval ==
                uint256(IPositionManagers.PositionManagerApproval.None),
            "ZR-04: Zap should have no PM approval after operation"
        );
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

    function _generateOneTimePermit(
        address user,
        uint256 pk
    ) internal returns (IEbtcZapRouterBase.PositionManagerPermit memory) {
        uint _deadline = (block.timestamp + deadline);
        IPositionManagers.PositionManagerApproval _approval = IPositionManagers
            .PositionManagerApproval
            .OneTime;

        // Generate signature to one-time approve zap
        bytes32 digest = _generatePermitSignature(
            user,
            address(zapRouter),
            _approval,
            _deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(pk, digest);

        IEbtcZapRouterBase.PositionManagerPermit memory pmPermit = IEbtcZapRouterBase
            .PositionManagerPermit(_deadline, v, r, s);
        return pmPermit;
    }
}