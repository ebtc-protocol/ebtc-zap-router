// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, console2} from "forge-std/Test.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IERC3156FlashLender} from "@ebtc/contracts/Interfaces/IERC3156FlashLender.sol";
import {ZapRouterBase} from "./ZapRouterBase.sol";
import {IEbtcZapRouter} from "./interface/IEbtcZapRouter.sol";

contract EbtcZapRouter is ZapRouterBase, IEbtcZapRouter {
    constructor(DeploymentParams memory params) ZapRouterBase(params) {}

    function temp_openCdpWithLeverage(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance, // margin balance
        PositionManagerPermit memory _positionManagerPermit,
        bytes calldata _exchangeData
    ) external returns (bytes32 cdpId) {
        // TODO: calculate this for real, need to figure out how to specify leverage ratio
        // TODO: check max leverage here once we know how leverage will be specified
        uint256 flAmount = _debtToCollateral(_debt);

        // We need to deposit slightly less collateral to account for fees / slippage
        // COLLATERAL_BUFFER is a temporary solution to make the tests pass
        // TODO: discuss this and see if it's better to pass in some sort of slippage setting
        uint256 totalCollateral = ((flAmount + _stEthBalance) * COLLATERAL_BUFFER) /
            SLIPPAGE_PRECISION;

        _permitPositionManagerApproval(_positionManagerPermit);

        cdpId = sortedCdps.toCdpId(msg.sender, block.number, sortedCdps.nextCdpNonce());

        OpenCdpOperation memory cdp;

        cdp.eBTCToMint = _debt;
        cdp._upperHint = _upperHint;
        cdp._lowerHint = _lowerHint;
        cdp.stETHToDeposit = totalCollateral;
        // specifying borrower here = openCdpFor
        cdp.borrower = msg.sender;

        _openCdpOperation({
            _cdpId: cdpId,
            _cdp: cdp,
            _flAmount: flAmount,
            _stEthBalance: _stEthBalance,
            _exchangeData: _exchangeData
        });

        // TODO: emit event
        // TODO: return cdpId, otherwise useful data? check with UI devs
    }

    function temp_closeCdpWithLeverage(
        bytes32 _cdpId,
        PositionManagerPermit memory _positionManagerPermit,
        uint256 maxSlippage,
        bytes calldata _exchangeData
    ) external {
        ICdpManagerData.Cdp memory cdpInfo = cdpManager.Cdps(_cdpId);

        uint256 flashFee = IERC3156FlashLender(address(borrowerOperations)).flashFee(
            address(ebtcToken),
            cdpInfo.debt
        );

        _permitPositionManagerApproval(_positionManagerPermit);

        _closeCdpOperation({
            _cdpId: _cdpId,
            _debt: cdpInfo.debt,
            _flashFee: flashFee,
            _maxSlippage: maxSlippage,
            _exchangeData: _exchangeData
        });

        // TODO: emit event
        // TODO: otherwise useful data? check with UI devs
    }

    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external {
        _openCdpWithPermit(_debt, _upperHint, _lowerHint, _stEthBalance, _positionManagerPermit);
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

        _permitPositionManagerApproval(_positionManagerPermit);

        borrowerOperations.openCdpFor(_debt, _upperHint, _lowerHint, _stEthBalance, msg.sender);

        ebtcToken.transfer(msg.sender, _debt);

        // Token balances should not have changed after operation
        // Created CDP should be owned by borrower
    }
}
