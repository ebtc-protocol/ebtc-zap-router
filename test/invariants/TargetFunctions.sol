// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {TargetContractSetup} from "@ebtc/contracts/TestContracts/invariants/TargetContractSetup.sol";
import {ICdpManager} from "@ebtc/contracts/interfaces/ICdpManager.sol";
import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {IStETH} from "../../src/interface/IStETH.sol";
import {ZapRouterProperties} from "../../src/invariants/ZapRouterProperties.sol";
import {EbtcZapRouter} from "../../src/EbtcZapRouter.sol";

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

    modifier setup() virtual {
        actor = actors[msg.sender];
        _;
    }

    function openCdpWithEth(
        uint256 _debt,
        uint256 _ethBalance
    ) public setup returns (bytes32 cdpId) {

    }

    function closeCdp(uint _i) public setup {

    }

    function adjustCdp(
        uint _i,
        uint _collWithdrawal,
        uint _EBTCChange,
        bool _isDebtIncrease
    ) public setup {
    
    }
}
