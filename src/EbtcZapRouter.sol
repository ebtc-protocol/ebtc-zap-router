// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IBorrowerOperations, IPositionManagers} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {LeverageMacroBase} from "@ebtc/contracts/LeverageMacroBase.sol";
import {IEbtcZapRouter} from "./interface/IEbtcZapRouter.sol";

contract EbtcZapRouter is LeverageMacroBase, IEbtcZapRouter {
    address internal immutable OWNER;

    constructor(DeploymentParams memory params) 
        LeverageMacroBase(
            params.borrowerOperations,
            params.activePool,
            params.cdpManager,
            params.ebtc,
            params.stEth,
            params.sortedCdps,
            true     
        ) {
        OWNER = msg.sender;

        // Infinite Approvals @TODO: do these stay at max for each token?
        ebtcToken.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(activePool), type(uint256).max);
    }

    function owner() public override returns (address) {
        return OWNER;
    }

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

    function openCdpWithEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _ethBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external payable {
        require(msg.value == _ethBalance, "EbtcZapRouter: Incorrect ETH amount");
        // Deposit to stEth
    }

    function openCdpWithWeth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wethBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external {
        // WETH -> ETH -> stETH
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
        // Unwrap to stETH
    }

    function _openCdpWithPermit(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) internal {
        // Check token balances of Zap before operation

        stETH.transferFrom(msg.sender, address(this), _stEthBalance);
        
        IPositionManagers(address(borrowerOperations)).permitPositionManagerApproval(
            msg.sender,
            address(this),
            IPositionManagers.PositionManagerApproval.OneTime,
            _positionManagerPermit.deadline,
            _positionManagerPermit.v,
            _positionManagerPermit.r,
            _positionManagerPermit.s
        );

        borrowerOperations.openCdpFor(_debt, _upperHint, _lowerHint, _stEthBalance, msg.sender);

        ebtcToken.transfer(msg.sender, _debt);

        // Token balances should not have changed after operation
        // Created CDP should be owned by borrower
    }
}
