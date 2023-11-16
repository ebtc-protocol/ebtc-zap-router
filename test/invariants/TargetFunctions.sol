// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@crytic/properties/contracts/util/Hevm.sol";
import {TargetContractSetup} from "@ebtc/contracts/TestContracts/invariants/TargetContractSetup.sol";
import {CollateralTokenTester} from "@ebtc/contracts/TestContracts/CollateralTokenTester.sol";
import {ICdpManager} from "@ebtc/contracts/interfaces/ICdpManager.sol";
import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {IStETH} from "../../src/interface/IStETH.sol";
import {ZapRouterProperties} from "../../src/invariants/ZapRouterProperties.sol";
import {EbtcZapRouter} from "../../src/EbtcZapRouter.sol";
import {ZapRouterActor} from "../../src/invariants/ZapRouterActor.sol";
import {IEbtcZapRouter} from "../../src/interface/IEbtcZapRouter.sol";

abstract contract TargetFunctions is TargetContractSetup, ZapRouterProperties {
    function setUp() public virtual {
        super._setUp();
        zapRouter = new EbtcZapRouter(
            IStETH(address(collateral)),
            IERC20(address(eBTCToken)),
            IBorrowerOperations(address(borrowerOperations)),
            ICdpManager(address(cdpManager))
        );
    }

    function setUpActors() internal {
        bool success;
        address[] memory tokens = new address[](2);
        tokens[0] = address(eBTCToken);
        tokens[1] = address(collateral);
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
            (success, ) = address(zapActors[addresses[i]]).call{
                value: INITIAL_ETH_BALANCE
            }("");
            assert(success);
            (success, ) = zapActors[addresses[i]].proxy(
                address(collateral),
                abi.encodeWithSelector(
                    CollateralTokenTester.deposit.selector,
                    ""
                ),
                INITIAL_COLL_BALANCE,
                false
            );
            assert(success);
        }
    }

    modifier setup() virtual {
        zapSender = msg.sender;
        zapActor = zapActors[msg.sender];
        zapActorKey = zapActorKeys[msg.sender];
        _;
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

    function openCdpWithEth(
        uint256 _debt,
        uint256 _ethBalance
    ) public setup returns (bytes32 cdpId) {
        bool success;
        bytes memory returnData;

        // TODO: Figure out the best way to clamp this
        // Is clamping necessary? Can we just let it revert?
        _debt = between(_debt, 1, 0.1e18);

        // we pass in CCR instead of MCR in case it's the first one
        uint price = priceFeedMock.getPrice();

        uint256 requiredCollAmount = (_debt * cdpManager.CCR()) / (price);
        uint256 minCollAmount = max(
            cdpManager.MIN_NET_STETH_BALANCE() + borrowerOperations.LIQUIDATOR_REWARD(),
            requiredCollAmount
        );
        uint256 maxCollAmount = min(2 * minCollAmount, INITIAL_COLL_BALANCE / 10);
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
    }

    function closeCdp(uint _i) public setup {
        bool success;
        bytes memory returnData;

        require(cdpManager.getActiveCdpsCount() > 1, "Cannot close last CDP");

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        t(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

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
    }

    function adjustCdp(
        uint _i,
        uint _collWithdrawal,
        uint _EBTCChange,
        bool _isDebtIncrease,
        uint _stEthBalanceIncrease
    ) public setup {
        bool success;
        bytes memory returnData;

        uint256 numberOfCdps = sortedCdps.cdpCountOf(address(actor));
        require(numberOfCdps > 0, "Actor must have at least one CDP open");

        _i = between(_i, 0, numberOfCdps - 1);
        bytes32 _cdpId = sortedCdps.cdpOfOwnerByIndex(address(actor), _i);
        t(_cdpId != bytes32(0), "CDP ID must not be null if the index is valid");

        {
            (uint256 entireDebt, uint256 entireColl) = cdpManager.getSyncedDebtAndCollShares(_cdpId);
            _collWithdrawal = between(_collWithdrawal, 0, entireColl);
            _EBTCChange = between(_EBTCChange, 0, entireDebt);

            _stEthBalanceIncrease = min(_stEthBalanceIncrease, (INITIAL_COLL_BALANCE / 10) - entireColl); 
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
    }
}
