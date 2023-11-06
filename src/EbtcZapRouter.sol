// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";

contract EbtcZapRouter {
    IERC20 public immutable stEth;
    IERC20 public immutable ebtc;
    IBorrowerOperations public immutable borrowerOperations;

    constructor(IERC20 _stEth, IERC20 _ebtc, IBorrowerOperations _borrowerOperations) {
        stEth = _stEth;
        ebtc = _ebtc;
        borrowerOperations = _borrowerOperations;

        // Infinite Approvals @TODO: do these stay at max for each token?
        stEth.approve(address(borrowerOperations), type(uint256).max);
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
         _openCdp(
            _debt,
            _upperHint,
            _lowerHint,
            _stEthBalance,
            _deadline,
            _v,
            _r,
            _s);
    }

    function _openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal {
        // Check token balances of Zap before operation

        stEth.transferFrom(msg.sender, address(this), _stEthBalance);
        
        borrowerOperations.permitPositionManagerApproval(
            msg.sender,
            address(this),
            IPositionManagers.PositionManagerApproval.OneTime,
            _deadline,
            _v,
            _r,
            _s
        );

        borrowerOperations.openCdpFor(_debt, _upperHint, _lowerHint, _stEthBalance, msg.sender);

        ebtc.transfer(msg.sender, _debt);

        // Token balances should not have changed after operation
        // Created CDP should be owned by borrower
    }
}
