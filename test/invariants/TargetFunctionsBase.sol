// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/Hevm.sol";
import {TargetContractSetup} from "@ebtc/contracts/TestContracts/invariants/TargetContractSetup.sol";
import {CollateralTokenTester} from "@ebtc/contracts/TestContracts/CollateralTokenTester.sol";
import {Mock1Inch} from "@ebtc/contracts/TestContracts/Mock1Inch.sol";
import {ICdpManager} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IBorrowerOperations} from "@ebtc/contracts/Interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/Interfaces/IPositionManagers.sol";
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
        zapActorAddrs = new address[](NUMBER_OF_ACTORS);
        for (uint i = 0; i < NUMBER_OF_ACTORS; i++) {
            zapActorAddrs[i] = addresses[i];
            zapActors[addresses[i]] = new ZapRouterActor(
                tokens,
                address(zapRouter),
                address(leverageZapRouter),
                addresses[i]
            );
        }
    }

    function setEthPerShare(uint256 _newEthPerShare) public setup {
        uint256 currentEthPerShare = collateral.getEthPerShare();
        _newEthPerShare = between(
            _newEthPerShare,
            (currentEthPerShare * 1e18) / MAX_REBASE_PERCENT,
            (currentEthPerShare * MAX_REBASE_PERCENT) / 1e18
        );
        collateral.setEthPerShare(_newEthPerShare);
    }
    
    function _dealETH(ZapRouterActor actor, uint256 amount) internal {
        (bool success, ) = address(actor).call{value: amount}("");
        assert(success);
    }

    function _dealWETH(ZapRouterActor actor, uint256 amount, bool useSender) internal {
        _dealETH(actor, amount);
        (bool success, ) = actor.proxy(
            address(testWeth),
            abi.encodeWithSelector(WETH9.deposit.selector, ""),
            amount,
            false
        );
        assert(success);
        if (useSender) {
            (success, ) = actor.proxy(
                address(testWeth),
                abi.encodeWithSelector(WETH9.transfer.selector, actor.sender(), amount),
                false
            );
        }
        assert(success);
    }

    function _dealCollateral(ZapRouterActor actor, uint256 amount, bool useSender) internal {
        _dealETH(actor, amount);
        uint256 amountBefore = IERC20(address(collateral)).balanceOf(address(actor));
        (bool success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(CollateralTokenTester.deposit.selector, ""),
            amount,
            false
        );
        uint256 amountAfter = IERC20(address(collateral)).balanceOf(address(actor));
        assert(success);
        if (useSender) {
            (success, ) = actor.proxy(
                address(collateral),
                abi.encodeWithSelector(
                    IERC20.transfer.selector,
                    actor.sender(),
                    amountAfter - amountBefore
                ),
                false
            );
            assert(success);
        }
    }

    function _dealWrappedCollateral(ZapRouterActor actor, uint256 amount, bool useSender) internal {
        _dealETH(actor, amount);
        (bool success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(CollateralTokenTester.deposit.selector, ""),
            amount,
            false
        );
        assert(success);
        (success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(
                CollateralTokenTester.approve.selector,
                address(testWstEth),
                amount
            ),
            false
        );
        assert(success);
        uint256 amountBefore = IERC20(testWstEth).balanceOf(address(actor));
        (success, ) = actor.proxy(
            testWstEth,
            abi.encodeWithSelector(WstETH.wrap.selector, amount),
            false
        );
        assert(success);
        uint256 amountAfter = IERC20(testWstEth).balanceOf(address(actor));
        if (useSender) {
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
    }

    function _checkApproval(address _user) internal {
        uint positionManagerApproval = uint256(
            borrowerOperations.getPositionManagerApproval(_user, address(zapRouter))
        );

        t(
            positionManagerApproval == uint256(IPositionManagers.PositionManagerApproval.None),
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
        address target,
        uint256 pk
    ) internal returns (IEbtcZapRouterBase.PositionManagerPermit memory) {
        uint _deadline = (block.timestamp + deadline);
        IPositionManagers.PositionManagerApproval _approval = IPositionManagers
            .PositionManagerApproval
            .OneTime;

        // Generate signature to one-time approve zap
        bytes32 digest = _generatePermitSignature(user, target, _approval, _deadline);
        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(pk, digest);

        IEbtcZapRouterBase.PositionManagerPermit memory pmPermit = IEbtcZapRouterBase
            .PositionManagerPermit(_deadline, v, r, s);
        return pmPermit;
    }
}
