// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {IStETH} from "./interface/IStETH.sol";
import {IEbtcZapRouter} from "./interface/IEbtcZapRouter.sol";

contract EbtcZapRouter is IEbtcZapRouter {
    IStETH public immutable stEth;
    IERC20 public immutable ebtc;
    IBorrowerOperations public immutable borrowerOperations;

    constructor(IStETH _stEth, IERC20 _ebtc, IBorrowerOperations _borrowerOperations) {
        stEth = _stEth;
        ebtc = _ebtc;
        borrowerOperations = _borrowerOperations;

        // Infinite Approvals @TODO: do these stay at max for each token?
        stEth.approve(address(borrowerOperations), type(uint256).max);
    }

    /// @dev Open a CDP with stEth
    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external {
         _openCdpWithPermit(
            _debt,
            _upperHint,
            _lowerHint,
            _stEthBalance,
            _positionManagerPermit
        );
    }

    /// @dev Open a CDP with stEth
    function openCdpWithEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _ethBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external payable {
        uint256 _stEthBalanceBefore = stEth.balanceOf(address(this));

        require(msg.value == _ethBalance, "EbtcZapRouter: Incorrect ETH amount");
        payable(address(stEth)).call{value: _ethBalance}("");

        uint256 _stEthBalanceAfter = stEth.balanceOf(address(this));
        uint256 _stEthBalance = _stEthBalanceAfter - _stEthBalanceBefore;

        _openCdpWithPermit(
            _debt,
            _upperHint,
            _lowerHint,
            _stEthBalance,
            _positionManagerPermit
        );
    }

    function openCdpWithWeth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wethBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external {
        revert("Not Implemented");
    }

    /// @notice Open CDP with WstETH as input token
    /// @param _debt Amount of debt to generate
    /// @param _upperHint Upper hint for CDP opening
    /// @param _lowerHint Lower hint for CDP opening
    /// @param _wstEthBalance Amount of WstETH to use. Will be converted to an stETH balance.
    function openCdpWithWstEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wstEthBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external {
        revert("Not Implemented");
    }

    function _openCdpWithPermit(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) internal {
        // Check token balances of Zap before operation

        stEth.transferFrom(msg.sender, address(this), _stEthBalance);
        
        borrowerOperations.permitPositionManagerApproval(
            msg.sender,
            address(this),
            IPositionManagers.PositionManagerApproval.OneTime,
            _positionManagerPermit.deadline,
            _positionManagerPermit.v,
            _positionManagerPermit.r,
            _positionManagerPermit.s
        );

        borrowerOperations.openCdpFor(_debt, _upperHint, _lowerHint, _stEthBalance, msg.sender);

        ebtc.transfer(msg.sender, _debt);

        // Token balances should not have changed after operation
        // Created CDP should be owned by borrower
    }
}
