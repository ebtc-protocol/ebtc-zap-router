// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, console2} from "forge-std/Test.sol";
import {IBorrowerOperations, IPositionManagers} from "@ebtc/contracts/Interfaces/IBorrowerOperations.sol";
import {IPriceFeed} from "@ebtc/contracts/Interfaces/IPriceFeed.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {LeverageMacroBase} from "./LeverageMacroBase.sol";
import {IEbtcZapRouter} from "./interface/IEbtcZapRouter.sol";

contract EbtcZapRouter is LeverageMacroBase, IEbtcZapRouter {
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant COLLATERAL_BUFFER_PRECISION = 1e4;
    /// @notice Collateral buffer used to account for slippage and fees
    /// 9995 = 0.05%
    uint256 internal constant COLLATERAL_BUFFER = 9995;

    address internal immutable theOwner;
    IPriceFeed internal immutable priceFeed;
    address internal immutable dex;

    constructor(
        DeploymentParams memory params
    )
        LeverageMacroBase(
            params.borrowerOperations,
            params.activePool,
            params.cdpManager,
            params.ebtc,
            params.stEth,
            params.sortedCdps,
            true
        )
    {
        theOwner = msg.sender;
        priceFeed = IPriceFeed(params.priceFeed);
        dex = params.dex;

        // Infinite Approvals @TODO: do these stay at max for each token?
        ebtcToken.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(activePool), type(uint256).max);
    }

    function owner() public override returns (address) {
        return theOwner;
    }

    // TODO: remove
    function temp_RequiredCollateral(uint256 _debt) public returns (uint256) {
        uint256 price = priceFeed.fetchPrice();
        return (_debt * PRECISION) / price;
    }

    function _getLeverageOperations(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        uint256 _totalCollateral,
        bytes calldata _exchangeData
    ) private view returns (LeverageMacroOperation memory) {
        OpenCdpOperation memory cdp;

        cdp.eBTCToMint = _debt;
        cdp._upperHint = _upperHint;
        cdp._lowerHint = _lowerHint;
        cdp.stETHToDeposit = _totalCollateral;
        // specifying borrower here = openCdpFor
        cdp.borrower = msg.sender;

        SwapOperation[] memory swaps = new SwapOperation[](1);

        swaps[0].tokenForSwap = address(ebtcToken);
        // TODO: approve target maybe different
        swaps[0].addressForApprove = dex;
        swaps[0].exactApproveAmount = _debt;
        swaps[0].addressForSwap = dex;
        // TODO: exchange data needs to be passed in for aggregators (i.e. ZeroEx)
        // this trade can be generated for now
        swaps[0].calldataForSwap = _exchangeData;
        // op.swapChecks TODO: add proper checks

        LeverageMacroOperation memory op;

        op.tokenToTransferIn = address(stETH);
        op.amountToTransferIn = _stEthBalance;
        op.operationType = OperationType.OpenCdpOperation;
        op.OperationData = abi.encode(cdp);
        op.swapsAfter = swaps;

        return op;
    }

    function _getPostCheckParams(
        bytes32 _cdpId,
        uint256 _debt,
        uint256 _totalCollateral,
        ICdpManagerData.Status _status
    ) private view returns (PostCheckParams memory) {
        return
            PostCheckParams({
                expectedDebt: CheckValueAndType({value: _debt, operator: Operator.lte}),
                expectedCollateral: CheckValueAndType({
                    value: _totalCollateral,
                    operator: Operator.gte
                }),
                cdpId: _cdpId,
                expectedStatus: _status,
                borrower: msg.sender
            });
    }

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
        uint256 flAmount = temp_RequiredCollateral(_debt);

        // We need to deposit slightly less collateral to account for fees / slippage
        // COLLATERAL_BUFFER is a temporary solution to make the tests pass
        // TODO: discuss this and see if it's better to pass in some sort of slippage setting
        uint256 totalCollateral = ((flAmount + _stEthBalance) * COLLATERAL_BUFFER) /
            COLLATERAL_BUFFER_PRECISION;

        _permitPositionManagerApproval(_positionManagerPermit);

        cdpId = sortedCdps.toCdpId(msg.sender, block.number, sortedCdps.nextCdpNonce());

        doOperation(
            FlashLoanType.stETH,
            flAmount,
            _getLeverageOperations(
                _debt,
                _upperHint,
                _lowerHint,
                _stEthBalance,
                totalCollateral,
                _exchangeData
            ),
            PostOperationCheck.openCdp,
            _getPostCheckParams(cdpId, _debt, totalCollateral, ICdpManagerData.Status.active)
        );

        // TODO: emit event
        // TODO: return cdpId, otherwise useful data? check with UI devs
    }

    // TODO: not done with this function yet
    function temp_closeCdpWithLeverage(
        bytes32 _cdpId,
        PositionManagerPermit memory _positionManagerPermit,
        bytes calldata _exchangeData
    ) external {
        ICdpManagerData.Cdp memory cdpInfo = cdpManager.Cdps(_cdpId);
        CloseCdpOperation memory cdp;

        cdp._cdpId = _cdpId;

        SwapOperation[] memory swaps = new SwapOperation[](1);

        swaps[0].tokenForSwap = address(stETH);
        // TODO: approve target maybe different
        swaps[0].addressForApprove = dex;
        swaps[0].exactApproveAmount = cdpInfo.coll;
        swaps[0].addressForSwap = dex;
        // TODO: exchange data needs to be passed in for aggregators (i.e. ZeroEx)
        // this trade can be generated for now
        swaps[0].calldataForSwap = _exchangeData;
        // op.swapChecks TODO: add proper checks

        LeverageMacroOperation memory op;

        op.tokenToTransferIn = address(0);
        op.amountToTransferIn = 0;
        op.operationType = OperationType.CloseCdpOperation;
        op.OperationData = abi.encode(cdp);
        op.swapsAfter = swaps;

        _permitPositionManagerApproval(_positionManagerPermit);

        doOperation(
            FlashLoanType.eBTC,
            cdpInfo.debt,
            op,
            PostOperationCheck.isClosed,
            _getPostCheckParams(_cdpId, 0, 0, ICdpManagerData.Status.closedByOwner)
        );
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

    function _permitPositionManagerApproval(
        PositionManagerPermit memory _positionManagerPermit
    ) private {
        borrowerOperations.permitPositionManagerApproval(
            msg.sender,
            address(this),
            IPositionManagers.PositionManagerApproval.OneTime,
            _positionManagerPermit.deadline,
            _positionManagerPermit.v,
            _positionManagerPermit.r,
            _positionManagerPermit.s
        );
    }
}
