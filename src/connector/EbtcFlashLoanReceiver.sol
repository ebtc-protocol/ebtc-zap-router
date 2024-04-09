pragma solidity 0.8.17;

import {IDSAAccount} from "../interface/IDSAAccount.sol";
import {LeverageMacroBase} from "./LeverageMacroBase.sol";

contract EbtcFlashLoanReceiver is LeverageMacroBase {
    constructor(
        address _borrowerOperationsAddress,
        address _activePool,
        address _cdpManager,
        address _ebtc,
        address _coll,
        address _sortedCdps,
        bool _sweepToCaller
    ) LeverageMacroBase(
        _borrowerOperationsAddress,
        _activePool,
        _cdpManager,
        _ebtc,
        _coll,
        _sortedCdps,
        _sweepToCaller
    ) {
        ebtcToken.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(activePool), type(uint256).max);
    }
}