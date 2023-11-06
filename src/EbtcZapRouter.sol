// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";

contract EbtcZapRouter {
    IBorrowerOperations immutable borrowerOperations;

    constructor(IBorrowerOperations _borrowerOperations) {
        borrowerOperations = _borrowerOperations;
    }

    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        // Check token balances of Zap before operation
        borrowerOperations.permitPositionManagerApproval(
            msg.sender,
            address(this),
            IPositionManagers.PositionManagerApproval.OneTime,
            _deadline,
            _v,
            _r,
            _s
        );

        borrowerOperations.getPositionManagerApproval(msg.sender, address(this));

        // Token balances should not have changed after operation
        // Created CDP should be owned by borrower
    }
}
