// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ICdpManagerData} from "@ebtc/contracts/interfaces/ICdpManagerData.sol";
import {ICdpManager} from "@ebtc/contracts/interfaces/ICdpManager.sol";
import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {SafeERC20} from "@ebtc/contracts/Dependencies/SafeERC20.sol";
import {IStETH} from "./interface/IStETH.sol";
import {IWrappedETH} from "./interface/IWrappedETH.sol";
import {IEbtcZapRouter} from "./interface/IEbtcZapRouter.sol";
import {IWstETH} from "./interface/IWstETH.sol";

contract EbtcZapRouter is IEbtcZapRouter {
    using SafeERC20 for IERC20;

    IStETH public immutable stEth;
    IERC20 public immutable ebtc;
    IERC20 public immutable wrappedEth;
    IERC20 public immutable wstEth;
    IBorrowerOperations public immutable borrowerOperations;
    ICdpManager public immutable cdpManager;
    address public immutable owner;

    constructor(
        IERC20 _wstEth,
        IERC20 _wEth,
        IStETH _stEth,
        IERC20 _ebtc,
        IBorrowerOperations _borrowerOperations,
        ICdpManager _cdpManager,
        address _owner
    ) {
        wstEth = _wstEth;
        wrappedEth = _wEth;
        stEth = _stEth;
        ebtc = _ebtc;
        borrowerOperations = _borrowerOperations;
        cdpManager = _cdpManager;
        owner = _owner;

        // Infinite Approvals @TODO: do these stay at max for each token?
        stEth.approve(address(borrowerOperations), type(uint256).max);
        wrappedEth.approve(address(wrappedEth), type(uint256).max);
        wstEth.approve(address(wstEth), type(uint256).max);
    }

    /// @dev This is to allow wrapped ETH related Zap
    receive() external payable {
        require(
            msg.sender == address(wrappedEth),
            "EbtcZapRouter: only allow Wrapped ETH to send Ether!"
        );
    }

    /// @dev Open a CDP with stEth
    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external returns (bytes32 cdpId) {
        uint256 _collVal = _transferInitialStETHFromCaller(_stEthBalance);
        return _openCdpWithPermit(
            _debt,
            _upperHint,
            _lowerHint,
            _collVal,
            _positionManagerPermit
        );
    }

    /// @dev Open a CDP with raw native Ether
    /// @param _debt The total expected debt for new CDP
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _ethBalance The total stETH collateral (converted from raw Ether) amount deposited (added) for the specified Cdp
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function openCdpWithEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _ethBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external payable returns (bytes32 cdpId) {
        uint256 _collVal = _convertRawEthToStETH(_ethBalance);

        return _openCdpWithPermit(
            _debt,
            _upperHint,
            _lowerHint,
            _collVal,
            _positionManagerPermit
        );
    }

    /// @dev Open a CDP with Wrapped Ether
    /// @param _debt The total expected debt for new CDP
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _wethBalance The total stETH collateral (converted from wrapped Ether) amount deposited (added) for the specified Cdp
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function openCdpWithWrappedEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wethBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external payable {
        uint256 _collVal = _convertWrappedEthToStETH(_wethBalance);

        _openCdpWithPermit(
            _debt,
            _upperHint,
            _lowerHint,
            _collVal,
            _positionManagerPermit
        );
    }

    /// @dev Open a CDP with Wrapped StETH
    /// @param _debt The total expected debt for new CDP
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _wstEthBalance The total stETH collateral (converted from wrapped stETH) amount deposited (added) for the specified Cdp
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function openCdpWithWstEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wstEthBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external payable {
        uint256 _collVal = _convertWstEthToStETH(_wstEthBalance);

        _openCdpWithPermit(
            _debt,
            _upperHint,
            _lowerHint,
            _collVal,
            _positionManagerPermit
        );
    }

    /// @dev Close a CDP
    /// @dev Note plain collateral(stETH) is returned no matter whatever asset is zapped in
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function closeCdp(
        bytes32 _cdpId,
        PositionManagerPermit memory _positionManagerPermit
    ) external {
        _closeCdpWithPermit(_cdpId, _positionManagerPermit);
    }

    /// @notice Function that allows various operations which might change both collateral (increase collateral with raw native Ether) and debt of a Cdp
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _stEthBalanceDecrease The total stETH collateral amount withdrawn from the specified Cdp
    /// @param _debtChange The total eBTC debt amount withdrawn or repaid for the specified Cdp
    /// @param _isDebtIncrease The flag (true or false) to indicate whether this is a eBTC token withdrawal (debt increase) or a repayment (debt reduce)
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _ethBalanceIncrease The total stETH collateral (converted from raw native Ether) amount deposited (added) for the specified Cdp
    function adjustCdpWithEth(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _ethBalanceIncrease,
        PositionManagerPermit memory _positionManagerPermit
    ) external payable {
        uint256 _stEthBalanceIncrease = _ethBalanceIncrease;
        if (_ethBalanceIncrease > 0) {
            _stEthBalanceIncrease = _convertRawEthToStETH(_ethBalanceIncrease);
        }

        _adjustCdpWithPermit(
            _cdpId,
            _stEthBalanceDecrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _stEthBalanceIncrease,
            _positionManagerPermit
        );
    }

    /// @notice Function that allows various operations which might change both collateral (increase collateral with wrapped Ether) and debt of a Cdp
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _stEthBalanceDecrease The total stETH collateral amount withdrawn from the specified Cdp
    /// @param _debtChange The total eBTC debt amount withdrawn or repaid for the specified Cdp
    /// @param _isDebtIncrease The flag (true or false) to indicate whether this is a eBTC token withdrawal (debt increase) or a repayment (debt reduce)
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _wethBalanceIncrease The total stETH collateral (converted from wrapped Ether) amount deposited (added) for the specified Cdp
    function adjustCdpWithWrappedEth(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wethBalanceIncrease,
        PositionManagerPermit memory _positionManagerPermit
    ) external payable {
        uint256 _stEthBalanceIncrease = _wethBalanceIncrease;
        if (_wethBalanceIncrease > 0) {
            _stEthBalanceIncrease = _convertWrappedEthToStETH(
                _wethBalanceIncrease
            );
        }

        _adjustCdpWithPermit(
            _cdpId,
            _stEthBalanceDecrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _stEthBalanceIncrease,
            _positionManagerPermit
        );
    }

    /// @notice Function that allows various operations which might change both collateral (increase collateral with wrapped Ether) and debt of a Cdp
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _stEthBalanceDecrease The total stETH collateral amount withdrawn from the specified Cdp
    /// @param _debtChange The total eBTC debt amount withdrawn or repaid for the specified Cdp
    /// @param _isDebtIncrease The flag (true or false) to indicate whether this is a eBTC token withdrawal (debt increase) or a repayment (debt reduce)
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _wstEthBalanceIncrease The total stETH collateral (converted from wrapped stETH) amount deposited (added) for the specified Cdp
    function adjustCdpWithWstEth(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wstEthBalanceIncrease,
        PositionManagerPermit memory _positionManagerPermit
    ) external payable {
        uint256 _stEthBalanceIncrease = _wstEthBalanceIncrease;
        if (_wstEthBalanceIncrease > 0) {
            _stEthBalanceIncrease = _convertWstEthToStETH(
                _wstEthBalanceIncrease
            );
        }

        _adjustCdpWithPermit(
            _cdpId,
            _stEthBalanceDecrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _stEthBalanceIncrease,
            _positionManagerPermit
        );
    }

    /// @notice Function that allows various operations which might change both collateral and debt of a Cdp
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _stEthBalanceDecrease The total stETH collateral amount withdrawn from the specified Cdp
    /// @param _debtChange The total eBTC debt amount withdrawn or repaid for the specified Cdp
    /// @param _isDebtIncrease The flag (true or false) to indicate whether this is a eBTC token withdrawal (debt increase) or a repayment (debt reduce)
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _stEthBalanceIncrease The total stETH collateral amount deposited (added) for the specified Cdp
    function adjustCdp(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalanceIncrease,
        PositionManagerPermit memory _positionManagerPermit
    ) external {
        _adjustCdpWithPermit(
            _cdpId,
            _stEthBalanceDecrease,
            _debtChange,
            _isDebtIncrease,
            _upperHint,
            _lowerHint,
            _stEthBalanceIncrease,
            _positionManagerPermit
        );
    }

    /// @dev Increase the collateral for given CDP with raw native Ether
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _ethBalanceIncrease The total stETH collateral (converted from raw Ether) amount deposited (added) for the specified Cdp
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function addCollWithEth(
        bytes32 _cdpId,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _ethBalanceIncrease,
        PositionManagerPermit memory _positionManagerPermit
    ) external payable {
        uint256 _stEthToAdd = _convertRawEthToStETH(_ethBalanceIncrease);

        _adjustCdpWithPermit(
            _cdpId,
            0,
            0,
            false,
            _upperHint,
            _lowerHint,
            _stEthToAdd,
            _positionManagerPermit
        );
    }

    /// @notice Transfer an arbitrary token back to you
    function sweepToken(address token, uint256 amount) public {
        require(owner == msg.sender, "Must be owner");

        if (amount > 0) {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    function _openCdpWithPermit(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) internal returns (bytes32 cdpId) {
        // Check token balances of Zap before operation
        require(
            stEth.balanceOf(address(this)) >= _stEthBalance,
            "EbtcZapRouter: not enough collateral for open!"
        );

        borrowerOperations.permitPositionManagerApproval(
            msg.sender,
            address(this),
            IPositionManagers.PositionManagerApproval.OneTime,
            _positionManagerPermit.deadline,
            _positionManagerPermit.v,
            _positionManagerPermit.r,
            _positionManagerPermit.s
        );

        cdpId = borrowerOperations.openCdpFor(
            _debt,
            _upperHint,
            _lowerHint,
            _stEthBalance,
            msg.sender
        );

        ebtc.transfer(msg.sender, _debt);

        // Token balances should not have changed after operation
        // Created CDP should be owned by borrower
    }

    function _closeCdpWithPermit(
        bytes32 _cdpId,
        PositionManagerPermit memory _positionManagerPermit
    ) internal {
        require(
            msg.sender == _getOwnerAddress(_cdpId),
            "EbtcZapRouter: not owner for close!"
        );

        // for debt repayment
        uint256 _debt = ICdpManagerData(address(cdpManager)).getSyncedCdpDebt(
            _cdpId
        );
        ebtc.transferFrom(msg.sender, address(this), _debt);

        borrowerOperations.permitPositionManagerApproval(
            msg.sender,
            address(this),
            IPositionManagers.PositionManagerApproval.OneTime,
            _positionManagerPermit.deadline,
            _positionManagerPermit.v,
            _positionManagerPermit.r,
            _positionManagerPermit.s
        );

        uint256 _collBalBefore = stEth.balanceOf(address(this));
        borrowerOperations.closeCdp(_cdpId);
        uint256 _collBalAfter = stEth.balanceOf(address(this));

        stEth.transfer(msg.sender, (_collBalAfter - _collBalBefore));
    }

    function _adjustCdpWithPermit(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalanceIncrease,
        PositionManagerPermit memory _positionManagerPermit
    ) internal {
        require(
            msg.sender == _getOwnerAddress(_cdpId),
            "EbtcZapRouter: not owner for adjust!"
        );
        require(
            (_stEthBalanceDecrease > 0 && _stEthBalanceIncrease == 0) ||
                (_stEthBalanceIncrease > 0 && _stEthBalanceDecrease == 0),
            "EbtcZapRouter: can't add and remove collateral at the same time!"
        );

        borrowerOperations.permitPositionManagerApproval(
            msg.sender,
            address(this),
            IPositionManagers.PositionManagerApproval.OneTime,
            _positionManagerPermit.deadline,
            _positionManagerPermit.v,
            _positionManagerPermit.r,
            _positionManagerPermit.s
        );

        // for debt decrease
        if (!isDebtIncrease && _debtChange > 0) {
            ebtc.transferFrom(msg.sender, address(this), _debtChange);
        }

        uint256 _collBalBefore = stEth.balanceOf(address(this));
        borrowerOperations.adjustCdpWithColl(
            _cdpId,
            _stEthBalanceDecrease,
            _debtChange,
            isDebtIncrease,
            _upperHint,
            _lowerHint,
            _stEthBalanceIncrease
        );
        uint256 _collBalAfter = stEth.balanceOf(address(this));

        // Send any withdrawn debt back to borrower
        if (isDebtIncrease && _debtChange > 0) {
            ebtc.transfer(msg.sender, _debtChange);
        }

        // Send any withdrawn collateral to back to borrower
        if (_stEthBalanceDecrease > 0) {
            stEth.transfer(msg.sender, (_collBalAfter - _collBalBefore));
        }
    }

    function _transferInitialStETHFromCaller(
        uint256 _initialStETH
    ) internal returns (uint256) {
        // check before-after balances for 1-wei corner case
        uint256 _balBefore = stEth.balanceOf(address(this));
        stEth.transferFrom(msg.sender, address(this), _initialStETH);
        uint256 _deposit = stEth.balanceOf(address(this)) - _balBefore;
        return _deposit;
    }

    function _convertRawEthToStETH(
        uint256 _initialETH
    ) internal returns (uint256) {
        require(
            msg.value == _initialETH,
            "EbtcZapRouter: Incorrect ETH amount"
        );
        return _depositRawEthIntoLido(_initialETH);
    }

    function _depositRawEthIntoLido(
        uint256 _initialETH
    ) internal returns (uint256) {
        // check before-after balances for 1-wei corner case
        uint256 _balBefore = stEth.balanceOf(address(this));
        // TODO call submit() with a referral?
        payable(address(stEth)).call{value: _initialETH}("");
        uint256 _deposit = stEth.balanceOf(address(this)) - _balBefore;
        return _deposit;
    }

    function _convertWrappedEthToStETH(
        uint256 _initialWETH
    ) internal returns (uint256) {
        uint256 _wETHBalBefore = wrappedEth.balanceOf(address(this));
        wrappedEth.transferFrom(msg.sender, address(this), _initialWETH);
        uint256 _wETHReiceived = wrappedEth.balanceOf(address(this)) -
            _wETHBalBefore;

        uint256 _rawETHBalBefore = address(this).balance;
        IWrappedETH(address(wrappedEth)).withdraw(_wETHReiceived);
        uint256 _rawETHConverted = address(this).balance - _rawETHBalBefore;
        return _depositRawEthIntoLido(_rawETHConverted);
    }

    function _convertWstEthToStETH(
        uint256 _initialWstETH
    ) internal returns (uint256) {
        require(
            wstEth.transferFrom(msg.sender, address(this), _initialWstETH),
            "EbtcZapRouter: transfer wstETH failure!"
        );

        uint256 _stETHBalBefore = stEth.balanceOf(address(this));
        IWstETH(address(wstEth)).unwrap(_initialWstETH);
        uint256 _stETHReiceived = stEth.balanceOf(address(this)) -
            _stETHBalBefore;

        return _stETHReiceived;
    }

    function _getOwnerAddress(bytes32 cdpId) internal pure returns (address) {
        uint256 _tmp = uint256(cdpId) >> 96;
        return address(uint160(_tmp));
    }
}
