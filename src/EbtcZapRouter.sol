// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IBorrowerOperations, IPositionManagers} from "@ebtc/contracts/Interfaces/IBorrowerOperations.sol";
import {IPriceFeed} from "@ebtc/contracts/Interfaces/IPriceFeed.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {LeverageMacroBase} from "./LeverageMacroBase.sol";
import {IEbtcZapRouter} from "./interface/IEbtcZapRouter.sol";

contract EbtcZapRouter is LeverageMacroBase, IEbtcZapRouter {
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
        return (_debt * 1e18) / price;
    }

    function _getLeverageOperations(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        uint256 totalCollateral,
        bytes calldata exchangeData
    ) private view returns (LeverageMacroOperation memory) {
        OpenCdpOperation memory cdp;

        cdp.eBTCToMint = _debt;
        cdp._upperHint = _upperHint;
        cdp._lowerHint = _lowerHint;
        cdp.stETHToDeposit = totalCollateral;

        SwapOperation[] memory swaps = new SwapOperation[](1);

        swaps[0].tokenForSwap = address(stETH);
        // TODO: approve target maybe different
        swaps[0].addressForApprove = dex;
        swaps[0].exactApproveAmount = _debt;
        swaps[0].addressForSwap = dex;
        // TODO: exchange data needs to be passed in for aggregators (i.e. ZeroEx)
        // this trade can be generated for now
        swaps[0].calldataForSwap = exchangeData;
        // op.swapChecks TODO: add proper checks

        LeverageMacroOperation memory op;

        op.tokenToTransferIn = address(stETH);
        op.amountToTransferIn = _stEthBalance;
        op.operationType = OperationType.OpenCdpOperation;
        op.OperationData = abi.encode(cdp);
        op.swapsAfter = swaps;

        return op;
    }

    function _getPostCheckParams(uint256 _debt, uint256 totalCollateral)
        private
        view
        returns (PostCheckParams memory)
    {
        return
            PostCheckParams({
                expectedDebt: CheckValueAndType({
                    value: _debt,
                    // TODO: maybe too tight?
                    operator: Operator.equal
                }),
                expectedCollateral: CheckValueAndType({
                    value: totalCollateral,
                    // TODO: maybe too tight?
                    operator: Operator.equal
                }),
                cdpId: bytes32(0), // Not used
                expectedStatus: ICdpManagerData.Status.active
            });
    }

    function temp_openCdpWithLeverage(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        PositionManagerPermit memory _positionManagerPermit,
        bytes calldata exchangeData
    ) external {
        uint256 flAmount = temp_RequiredCollateral(_debt);
        uint256 totalCollateral = flAmount + _stEthBalance;

        IPositionManagers(address(borrowerOperations))
            .permitPositionManagerApproval(
                msg.sender,
                address(this),
                IPositionManagers.PositionManagerApproval.OneTime,
                _positionManagerPermit.deadline,
                _positionManagerPermit.v,
                _positionManagerPermit.r,
                _positionManagerPermit.s
            );

        doOperation(
            FlashLoanType.stETH,
            flAmount,
            _getLeverageOperations(
                _debt,
                _upperHint,
                _lowerHint,
                _stEthBalance,
                totalCollateral,
                exchangeData
            ),
            PostOperationCheck.openCdp,
            _getPostCheckParams(_debt, totalCollateral)
        );
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
        require(
            msg.value == _ethBalance,
            "EbtcZapRouter: Incorrect ETH amount"
        );
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

        IPositionManagers(address(borrowerOperations))
            .permitPositionManagerApproval(
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

        ebtcToken.transfer(msg.sender, _debt);

        // Token balances should not have changed after operation
        // Created CDP should be owned by borrower
    }
}
