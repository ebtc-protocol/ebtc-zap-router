// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IPriceFeed} from "@ebtc/contracts/Interfaces/IPriceFeed.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IBorrowerOperations, IPositionManagers} from "@ebtc/contracts/LeverageMacroBase.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {IEbtcZapRouterBase} from "./interface/IEbtcZapRouterBase.sol";
import {IWrappedETH} from "./interface/IWrappedETH.sol";
import {IStETH} from "./interface/IStETH.sol";
import {IWstETH} from "./interface/IWstETH.sol";

interface IMinChangeGetter {
    function MIN_CHANGE() external view returns (uint256);
}

abstract contract ZapRouterBase is IEbtcZapRouterBase {
    address public constant NATIVE_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public constant LIQUIDATOR_REWARD = 2e17;
    uint256 public constant MIN_NET_STETH_BALANCE = 2e18;
    uint256 public immutable MIN_CHANGE;

    IERC20 public immutable wstEth;
    IStETH public immutable stEth;
    IERC20 public immutable wrappedEth;

    constructor(address _borrowerOperations, IERC20 _wstEth, IERC20 _wEth, IStETH _stEth) {
        MIN_CHANGE = IMinChangeGetter(_borrowerOperations).MIN_CHANGE();
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

    function _transferStEthToCaller(
        bytes32 _cdpId,
        EthVariantZapOperationType _operationType,
        bool _useWstETH,
        uint256 _stEthVal
    ) internal {
        if (_useWstETH) {
            // return wrapped version(WstETH)
            uint256 _wstETHVal = IWstETH(address(wstEth)).wrap(_stEthVal);
            emit ZapOperationEthVariant(
                _cdpId,
                _operationType,
                false,
                address(wstEth),
                _wstETHVal,
                _stEthVal,
                msg.sender
            );

            wstEth.transfer(msg.sender, _wstETHVal);
        } else {
            // return original collateral(stETH)
            emit ZapOperationEthVariant(
                _cdpId,
                _operationType,
                false,
                address(stEth),
                _stEthVal,
                _stEthVal,
                msg.sender
            );
            stEth.transfer(msg.sender, _stEthVal);
        }
    }

    function _transferInitialStETHFromCaller(uint256 _initialStETH) internal returns (uint256) {
        // check before-after balances for 1-wei corner case
        uint256 _balBefore = stEth.balanceOf(address(this));
        stEth.transferFrom(msg.sender, address(this), _initialStETH);
        uint256 _deposit = stEth.balanceOf(address(this)) - _balBefore;
        return _deposit;
    }

    function _permitPositionManagerApproval(
        IBorrowerOperations borrowerOperations,
        PositionManagerPermit memory _positionManagerPermit
    ) internal {
        try
            borrowerOperations.permitPositionManagerApproval(
                msg.sender,
                address(this),
                IPositionManagers.PositionManagerApproval.OneTime,
                _positionManagerPermit.deadline,
                _positionManagerPermit.v,
                _positionManagerPermit.r,
                _positionManagerPermit.s
            )
        {} catch {
            /// @notice adding try...catch around to mitigate potential permit front-running
            /// see: https://www.trust-security.xyz/post/permission-denied
        }
    }

    function _requireZeroOrMinAdjustment(uint256 _change) internal view {
        require(
            _change == 0 || _change >= MIN_CHANGE,
            "ZapRouterBase: Debt or collateral change must be zero or above min"
        );
    }

    function _requireAtLeastMinNetStEthBalance(uint256 _stEthBalance) internal pure {
        require(
            _stEthBalance >= MIN_NET_STETH_BALANCE,
            "ZapRouterBase: Cdp's net stEth balance must not fall below minimum"
        );
    }

    function _getOwnerAddress(bytes32 cdpId) internal pure returns (address) {
        uint256 _tmp = uint256(cdpId) >> 96;
        return address(uint160(_tmp));
    }
}
