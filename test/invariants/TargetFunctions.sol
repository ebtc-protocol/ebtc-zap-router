// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/Hevm.sol";
import {TargetContractSetup} from "@ebtc/contracts/TestContracts/invariants/TargetContractSetup.sol";
import {CollateralTokenTester} from "@ebtc/contracts/TestContracts/CollateralTokenTester.sol";
import {ICdpManager} from "@ebtc/contracts/interfaces/ICdpManager.sol";
import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {WETH9} from "@ebtc/contracts/TestContracts/WETH9.sol";
import {IStETH} from "../../src/interface/IStETH.sol";
import {ZapRouterProperties} from "../../src/invariants/ZapRouterProperties.sol";
import {EbtcZapRouter} from "../../src/EbtcZapRouter.sol";
import {ZapRouterActor} from "../../src/invariants/ZapRouterActor.sol";
import {IEbtcZapRouter} from "../../src/interface/IEbtcZapRouter.sol";
import {WstETH} from "../../src/testContracts/WstETH.sol";

abstract contract TargetFunctions is TargetContractSetup, ZapRouterProperties {
    function setUp() public virtual {
        super._setUp();
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
    }

    function _dealETH(ZapRouterActor actor) private {
        (bool success, ) = address(actor).call{value: INITIAL_ETH_BALANCE}("");
        assert(success);
    }

    function _dealWETH(ZapRouterActor actor) private {
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

    function _dealCollateral(ZapRouterActor actor) private {
        _dealETH(actor);
        (bool success, ) = actor.proxy(
            address(collateral),
            abi.encodeWithSelector(CollateralTokenTester.deposit.selector, ""),
            INITIAL_COLL_BALANCE,
            false
        );
        assert(success);
    }

    function _dealWrappedCollateral(ZapRouterActor actor) private {
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
            abi.encodeWithSelector(IERC20.transfer.selector, actor.sender(), amountAfter - amountBefore),
            false
        );
        assert(success);        
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
                addresses[i]
            );
        }
    }

    modifier setup() virtual {
        zapSender = msg.sender;
        zapActor = zapActors[msg.sender];
        zapActorKey = zapActorKeys[msg.sender];
        _;
    }

    function _checkApproval(address _user) private {
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
    ) internal returns (IEbtcZapRouter.PositionManagerPermit memory) {
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

        IEbtcZapRouter.PositionManagerPermit memory pmPermit = IEbtcZapRouter
            .PositionManagerPermit(_deadline, v, r, s);
        return pmPermit;
    }

    function openCdpWithEth(uint256 _debt, uint256 _ethBalance) public setup {
        _dealETH(zapActor);

        bool success;
        bytes memory returnData;

        // TODO: Figure out the best way to clamp this
        // Is clamping necessary? Can we just let it revert?
        _debt = between(_debt, 1, 0.1e18);

        // we pass in CCR instead of MCR in case it's the first one
        uint price = priceFeedMock.getPrice();

        uint256 requiredCollAmount = (_debt * cdpManager.CCR()) / (price);
        uint256 minCollAmount = max(
            cdpManager.MIN_NET_STETH_BALANCE() +
                borrowerOperations.LIQUIDATOR_REWARD(),
            requiredCollAmount
        );
        uint256 maxCollAmount = min(
            2 * minCollAmount,
            INITIAL_COLL_BALANCE / 10
        );
        _ethBalance = between(requiredCollAmount, minCollAmount, maxCollAmount);

        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                zapActorKey
            );

        (success, returnData) = zapActor.proxy(
            address(zapRouter),
            abi.encodeWithSelector(
                IEbtcZapRouter.openCdpWithEth.selector,
                _debt,
                bytes32(0),
                bytes32(0),
                _ethBalance,
                pmPermit
            ),
            _ethBalance,
            true
        );
        t(success, "Call shouldn't fail");

        _checkApproval(address(zapSender));
    }

    function openCdpWithWrappedEth(
        uint256 _debt,
        uint256 _wethBalance
    ) public setup {
        _dealWETH(zapActor);

        bool success;
        bytes memory returnData;

        // TODO: Figure out the best way to clamp this
        // Is clamping necessary? Can we just let it revert?
        _debt = between(_debt, 1, 0.1e18);

        // we pass in CCR instead of MCR in case it's the first one
        uint price = priceFeedMock.getPrice();

        uint256 requiredCollAmount = (_debt * cdpManager.CCR()) / (price);
        uint256 minCollAmount = max(
            cdpManager.MIN_NET_STETH_BALANCE() +
                borrowerOperations.LIQUIDATOR_REWARD(),
            requiredCollAmount
        );
        uint256 maxCollAmount = min(
            2 * minCollAmount,
            INITIAL_COLL_BALANCE / 10
        );
        _wethBalance = between(
            requiredCollAmount,
            minCollAmount,
            maxCollAmount
        );

        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                zapActorKey
            );

        (success, returnData) = zapActor.proxy(
            address(zapRouter),
            abi.encodeWithSelector(
                IEbtcZapRouter.openCdpWithWrappedEth.selector,
                _debt,
                bytes32(0),
                bytes32(0),
                _wethBalance,
                pmPermit
            ),
            true
        );
        t(success, "Call shouldn't fail");

        _checkApproval(address(zapSender));
    }

    function openCdpWithWstEth(
        uint256 _debt,
        uint256 _wstEthBalance
    ) public setup {
        _dealWrappedCollateral(zapActor);

        bool success;
        bytes memory returnData;

        // TODO: Figure out the best way to clamp this
        // Is clamping necessary? Can we just let it revert?
        _debt = between(_debt, 1, 0.1e18);

        // we pass in CCR instead of MCR in case it's the first one
        uint price = priceFeedMock.getPrice();

        uint256 requiredCollAmount = (_debt * cdpManager.CCR()) / (price);
        uint256 minCollAmount = max(
            cdpManager.MIN_NET_STETH_BALANCE() +
                borrowerOperations.LIQUIDATOR_REWARD(),
            requiredCollAmount
        );
        uint256 maxCollAmount = min(
            2 * minCollAmount,
            INITIAL_COLL_BALANCE / 10
        );
        _wstEthBalance = between(
            requiredCollAmount,
            minCollAmount,
            maxCollAmount
        );

        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                zapActorKey
            );

        (success, returnData) = zapActor.proxy(
            address(zapRouter),
            abi.encodeWithSelector(
                IEbtcZapRouter.openCdpWithWstEth.selector,
                _debt,
                bytes32(0),
                bytes32(0),
                _wstEthBalance,
                pmPermit
            ),
            true
        );
        t(success, "Call shouldn't fail");

        _checkApproval(address(zapSender));
    }

    function closeCdp(uint _i) public setup {
        bool success;
        bytes memory returnData;

        require(cdpManager.getActiveCdpsCount() > 1, "Cannot close last CDP");

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        t(
            _cdpId != bytes32(0),
            "CDP ID must not be null if the index is valid"
        );

        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                zapActorKey
            );

        (success, returnData) = zapActor.proxy(
            address(zapRouter),
            abi.encodeWithSelector(
                IEbtcZapRouter.closeCdp.selector,
                _cdpId,
                pmPermit
            ),
            true
        );
        t(success, "Call shouldn't fail");

        _checkApproval(address(zapSender));
    }

    function adjustCdp(
        uint _i,
        uint _collWithdrawal,
        uint _EBTCChange,
        bool _isDebtIncrease,
        uint _stEthBalanceIncrease
    ) public setup {
        _dealCollateral(zapActor);

        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        t(
            _cdpId != bytes32(0),
            "CDP ID must not be null if the index is valid"
        );

        {
            (uint256 entireDebt, uint256 entireColl) = cdpManager
                .getSyncedDebtAndCollShares(_cdpId);
            _collWithdrawal = between(_collWithdrawal, 0, entireColl);
            _EBTCChange = between(_EBTCChange, 0, entireDebt);

            _stEthBalanceIncrease = min(
                _stEthBalanceIncrease,
                (INITIAL_COLL_BALANCE / 10) - entireColl
            );
        }

        IEbtcZapRouter.PositionManagerPermit
            memory pmPermit = _generateOneTimePermit(
                address(zapSender),
                zapActorKey
            );

        (success, returnData) = zapActor.proxy(
            address(zapRouter),
            abi.encodeWithSelector(
                IEbtcZapRouter.adjustCdp.selector,
                _cdpId,
                _collWithdrawal,
                _EBTCChange,
                _isDebtIncrease,
                bytes32(0),
                bytes32(0),
                _stEthBalanceIncrease,
                pmPermit
            ),
            true
        );
        t(success, "Call shouldn't fail");

        _checkApproval(address(zapSender));
    }

    function adjustCdpWithWrappedEth(
        uint _i,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        uint256 _wethBalanceIncrease
    ) public setup {
        _dealWETH(zapActor);

        bool success;
        bytes memory returnData;
    }

    function adjustCdpWithWstEth(
        uint _i,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        uint256 _wstEthBalanceIncrease
    ) public setup {
        _dealWrappedCollateral(zapActor);

        bool success;
        bytes memory returnData;
    }
}
