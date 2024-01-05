// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IPositionManagers} from "@ebtc/contracts/Interfaces/IBorrowerOperations.sol";
import {IPriceFeed} from "@ebtc/contracts/Interfaces/IPriceFeed.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {LeverageMacroBase} from "@ebtc/contracts/LeverageMacroBase.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {IEbtcZapRouter} from "./interface/IEbtcZapRouter.sol";
import {IWrappedETH} from "./interface/IWrappedETH.sol";
import {IStETH} from "./interface/IStETH.sol";
import {IWstETH} from "./interface/IWstETH.sol";

abstract contract ZapRouterBase {
    IERC20 public immutable wstEth;
    IStETH public immutable stEth;
    IERC20 public immutable wrappedEth;

    constructor(IERC20 _wstEth, IERC20 _wEth, IStETH _stEth) {
        wstEth = _wstEth;
        wrappedEth = _wEth;
        stEth = _stEth;
    }

    function _depositRawEthIntoLido(uint256 _initialETH) internal returns (uint256) {
        // check before-after balances for 1-wei corner case
        uint256 _balBefore = stEth.balanceOf(address(this));
        // TODO call submit() with a referral?
        payable(address(stEth)).call{value: _initialETH}("");
        uint256 _deposit = stEth.balanceOf(address(this)) - _balBefore;
        return _deposit;
    }

    function _convertWrappedEthToStETH(uint256 _initialWETH) internal returns (uint256) {
        uint256 _wETHBalBefore = wrappedEth.balanceOf(address(this));
        wrappedEth.transferFrom(msg.sender, address(this), _initialWETH);
        uint256 _wETHReiceived = wrappedEth.balanceOf(address(this)) - _wETHBalBefore;

        uint256 _rawETHBalBefore = address(this).balance;
        IWrappedETH(address(wrappedEth)).withdraw(_wETHReiceived);
        uint256 _rawETHConverted = address(this).balance - _rawETHBalBefore;
        return _depositRawEthIntoLido(_rawETHConverted);
    }

    function _convertRawEthToStETH(uint256 _initialETH) internal returns (uint256) {
        require(msg.value == _initialETH, "EbtcZapRouter: Incorrect ETH amount");
        return _depositRawEthIntoLido(_initialETH);
    }

    function _convertWstEthToStETH(uint256 _initialWstETH) internal returns (uint256) {
        require(
            wstEth.transferFrom(msg.sender, address(this), _initialWstETH),
            "EbtcZapRouter: transfer wstETH failure!"
        );

        uint256 _stETHBalBefore = stEth.balanceOf(address(this));
        IWstETH(address(wstEth)).unwrap(_initialWstETH);
        uint256 _stETHReiceived = stEth.balanceOf(address(this)) - _stETHBalBefore;

        return _stETHReiceived;
    }
}
