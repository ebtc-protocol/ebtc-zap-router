// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ICdpManagerData} from "@ebtc/contracts/interfaces/ICdpManagerData.sol";
import {ICdpManager} from "@ebtc/contracts/interfaces/ICdpManager.sol";
import {IBorrowerOperations} from "@ebtc/contracts/interfaces/IBorrowerOperations.sol";
import {IPositionManagers} from "@ebtc/contracts/interfaces/IPositionManagers.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {IStETH} from "./interface/IStETH.sol";
import {IEbtcZapRouter} from "./interface/IEbtcZapRouter.sol";

contract EbtcZapRouter is IEbtcZapRouter {
    IStETH public immutable stEth;
    IERC20 public immutable ebtc;
    IBorrowerOperations public immutable borrowerOperations;
    ICdpManager public immutable cdpManager;

    constructor(
        IStETH _stEth,
        IERC20 _ebtc,
        IBorrowerOperations _borrowerOperations,
        ICdpManager _cdpManager
    ) {
        stEth = _stEth;
        ebtc = _ebtc;
        borrowerOperations = _borrowerOperations;
        cdpManager = _cdpManager;

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
        uint256 _collVal = _transferInitialStETHFromCaller(_stEthBalance);
        _openCdpWithPermit(
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
    ) external payable {
        uint256 _collVal = _convertRawEthToStETH(_ethBalance);

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
    ) external payable {
        _closeCdpWithPermit(_cdpId, _positionManagerPermit);
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

    /// @dev Retrieve some collateral from given CDP.
    /// @dev Note plain collateral(stETH) is returned no matter whatever original asset is zapped in
    /// @param _cdpId The CdpId on which this operation is operated
    /// @param _upperHint The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
    /// @param _lowerHint The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
    /// @param _stETHDecrease The total stETH collateral amount withdrawn from the specified Cdp
    /// @param _positionManagerPermit PositionPermit required for Zap approved by calling user
    function withdrawColl(
        bytes32 _cdpId,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stETHDecrease,
        PositionManagerPermit memory _positionManagerPermit
    ) external payable {
        _adjustCdpWithPermit(
            _cdpId,
            _stETHDecrease,
            0,
            false,
            _upperHint,
            _lowerHint,
            0,
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

        borrowerOperations.openCdpFor(
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

        // for debt increase
        if (isDebtIncrease && _debtChange > 0) {
            ebtc.transfer(msg.sender, _debtChange);
        }

        // for collateral decrease
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
        // check before-after balances for 1-wei corner case
        uint256 _balBefore = stEth.balanceOf(address(this));

        require(
            msg.value == _initialETH,
            "EbtcZapRouter: Incorrect ETH amount"
        );
        // TODO call submit() with a referral?
        payable(address(stEth)).call{value: _initialETH}("");

        uint256 _deposit = stEth.balanceOf(address(this)) - _balBefore;
        return _deposit;
    }

    function _getOwnerAddress(bytes32 cdpId) internal pure returns (address) {
        uint256 _tmp = uint256(cdpId) >> 96;
        return address(uint160(_tmp));
    }
}
