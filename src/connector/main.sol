pragma solidity 0.8.17;

import "./events.sol";
import "./helpers.sol";
import {TokenInterface} from "../common/interfaces.sol";
import {Stores} from "../common/stores.sol";
import {LeverageZapRouterBase} from "../LeverageZapRouterBase.sol";
import {IEbtcLeverageZapRouter} from "../interface/IEbtcLeverageZapRouter.sol";
import {IBorrowerOperations, IPositionManagers} from "@ebtc/contracts/LeverageMacroBase.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {ILeverageMacroBase} from "../interface/ILeverageMacroBase.sol";
import "@ebtc/contracts/Dependencies/SafeERC20.sol";
import "@ebtc/contracts/Interfaces/ISortedCdps.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManagerData.sol";

interface IEbtcFlashLoanReceiver is ILeverageMacroBase {
    function doOperation(
        FlashLoanType flType,
        uint256 borrowAmount,
        LeverageMacroOperation calldata operation,
        PostOperationCheck postCheckType,
        PostCheckParams calldata checkParams
    ) external;
}

abstract contract BadgerZapRouter is Helpers, Events, Stores, ILeverageMacroBase {
    using SafeERC20 for IERC20;

    IEbtcFlashLoanReceiver public immutable flashLoanReceiver;
    address public immutable stETH;
    address public immutable ebtcToken;
    ISortedCdps public immutable sortedCdps;
    IBorrowerOperations public immutable borrowerOperations;
    address public immutable dex;

    constructor(
        address _flashLoanReceiver, 
        address _borrowerOperations, 
        address _stETH, 
        address _ebtcToken, 
        address _sortedCdps,
        address _dex
    ) {
        flashLoanReceiver = IEbtcFlashLoanReceiver(_flashLoanReceiver);
        stETH = _stETH;
        ebtcToken = _ebtcToken;
        sortedCdps = ISortedCdps(_sortedCdps);
        borrowerOperations = IBorrowerOperations(_borrowerOperations);
        dex = _dex;
    }

    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _stEthMarginAmount,
        uint256 _stEthDepositAmount,
        IEbtcLeverageZapRouter.TradeData calldata _tradeData,
        uint256 getId,
        uint256 setId
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        TokenInterface(stETH).approve(address(borrowerOperations), _stEthDepositAmount);

        bytes32 cdpId = sortedCdps.toCdpId(
            address(this),
            block.number,
            sortedCdps.nextCdpNonce()
        );

        OpenCdpOperation memory cdp;

        cdp.eBTCToMint = _debt;
        cdp._upperHint = _upperHint;
        cdp._lowerHint = _lowerHint;
        cdp.stETHToDeposit = _stEthDepositAmount;

        _openCdpOperation({
            _cdpId: cdpId,
            _cdp: cdp,
            _flAmount: _stEthLoanAmount,
            _stEthBalance: _stEthMarginAmount,
            _tradeData: _tradeData
        });


//        setUint(setId, uint256(cdpId));
    }

    function _openCdpOperation(
        bytes32 _cdpId,
        OpenCdpOperation memory _cdp,
        uint256 _flAmount,
        uint256 _stEthBalance,
        IEbtcLeverageZapRouter.TradeData calldata _tradeData
    ) internal {
        LeverageMacroOperation memory op;

        op.tokenToTransferIn = address(stETH);
        op.amountToTransferIn = 0;
        op.operationType = OperationType.OpenCdpOperation;
        op.OperationData = abi.encode(_cdp);
        op.swapsAfter = _getSwapOperations(address(ebtcToken), address(stETH), _cdp.eBTCToMint, _tradeData);

        //uint256 ebtcBalBefore = ebtcToken.balanceOf(address(this));

        flashLoanReceiver.doOperation(
            FlashLoanType.stETH,
            _flAmount,
            op,
            PostOperationCheck.openCdp,
            _getPostCheckParams(
                _cdpId,
                _cdp.eBTCToMint,
                _cdp.stETHToDeposit,
                ICdpManagerData.Status.active
            )
        );

//        _sweepEbtc();
//        _sweepStEth();
    }

    function _getPostCheckParams(
        bytes32 _cdpId,
        uint256 _debt,
        uint256 _totalCollateral,
        ICdpManagerData.Status _status
    ) internal view returns (PostCheckParams memory) {
        return
            PostCheckParams({
                expectedDebt: CheckValueAndType({value: _debt, operator: Operator.equal}),
                expectedCollateral: CheckValueAndType({
                    value: _totalCollateral,
                    operator: Operator.skip
                }),
                cdpId: _cdpId,
                expectedStatus: _status
            });
    }

    function _getSwapOperations(
        address _tokenIn,
        address _tokenOut,
        uint256 _exactApproveAmount,
        IEbtcLeverageZapRouter.TradeData calldata _tradeData
    ) internal view returns (SwapOperation[] memory swaps) {
        swaps = new SwapOperation[](1);

        swaps[0].tokenForSwap = _tokenIn;
        // TODO: approve target maybe different
        swaps[0].addressForApprove = dex;
        swaps[0].exactApproveAmount = _exactApproveAmount;
        swaps[0].addressForSwap = dex;
        swaps[0].calldataForSwap = _tradeData.exchangeData;
        if (_tradeData.performSwapChecks) {
            swaps[0].swapChecks = _getSwapChecks(_tokenOut, _tradeData.expectedMinOut);            
        }
    }

    function _getSwapChecks(address tokenToCheck, uint256 expectedMinOut) 
        internal view returns (SwapCheck[] memory checks) {
        checks = new SwapCheck[](1);

        checks[0].tokenToCheck = tokenToCheck;
        checks[0].expectedMinOut = expectedMinOut;
    }

    /// @dev Must be memory since we had to decode it
    function handleOperation(
        address token,
        uint256 amount,
        uint256 fee,
        LeverageMacroOperation memory operation
    ) external {
        require(msg.sender == address(flashLoanReceiver));

        uint256 beforeSwapsLength = operation.swapsBefore.length;
        if (beforeSwapsLength > 0) {
            _doSwaps(operation.swapsBefore);
        }

        // Based on the type we do stuff
        if (operation.operationType == OperationType.OpenCdpOperation) {
            _openCdpCallback(operation.OperationData);
        }/* else if (operation.operationType == OperationType.OpenCdpForOperation) {
            _openCdpForCallback(operation.OperationData);
        } else if (operation.operationType == OperationType.CloseCdpOperation) {
            _closeCdpCallback(operation.OperationData);
        } else if (operation.operationType == OperationType.AdjustCdpOperation) {
            _adjustCdpCallback(operation.OperationData);
        } else if (operation.operationType == OperationType.ClaimSurplusOperation) {
            _claimSurplusCallback();
        }*/

        uint256 afterSwapsLength = operation.swapsAfter.length;
        if (afterSwapsLength > 0) {
            _doSwaps(operation.swapsAfter);
        }

        IERC20(token).transfer(address(flashLoanReceiver), amount + fee);
    }

    /// @dev Must be memory since we had to decode it
    function _doSwaps(SwapOperation[] memory swapData) internal {
        uint256 swapLength = swapData.length;

        for (uint256 i; i < swapLength; ) {
            _doSwap(swapData[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Given a SwapOperation
    ///     Approves the `addressForApprove` for the exact amount
    ///     Calls `addressForSwap`
    ///     Resets the approval of `addressForApprove`
    ///     Performs validation via `_doSwapChecks`
    function _doSwap(SwapOperation memory swapData) internal {
        // Ensure call is safe
        // Block all system contracts
        //_ensureNotSystem(swapData.addressForSwap);

        // Exact approve
        // Approve can be given anywhere because this is a router, and after call we will delete all approvals
        IERC20(swapData.tokenForSwap).safeApprove(
            swapData.addressForApprove,
            swapData.exactApproveAmount
        );

        // Call and perform swap
        // NOTE: Technically approval may be different from target, something to keep in mind
        // Call target are limited
        // But technically you could approve w/e you want here, this is fine because the contract is a router and will not hold user funds
        (bool success, ) = excessivelySafeCall(
            swapData.addressForSwap,
            gasleft(),
            0,
            0,
            swapData.calldataForSwap
        );
        require(success, "Call has failed");

        // Approve back to 0
        // Enforce exact approval
        // Can use max because the tokens are OZ
        // val -> 0 -> 0 -> val means this is safe to repeat since even if full approve is unused, we always go back to 0 after
        IERC20(swapData.tokenForSwap).safeApprove(swapData.addressForApprove, 0);

        // Do the balance checks after the call to the aggregator
  //      _doSwapChecks(swapData.swapChecks);
    }

    /// @dev excessivelySafeCall to perform generic calls without getting gas bombed | useful if you don't care about return value
    /// @notice Credits to: https://github.com/nomad-xyz/ExcessivelySafeCall/blob/main/src/ExcessivelySafeCall.sol
    function excessivelySafeCall(
        address _target,
        uint256 _gas,
        uint256 _value,
        uint16 _maxCopy,
        bytes memory _calldata
    ) internal returns (bool, bytes memory) {
        // set up for assembly call
        uint256 _toCopy;
        bool _success;
        bytes memory _returnData = new bytes(_maxCopy);
        // dispatch message to recipient
        // by assembly calling "handle" function
        // we call via assembly to avoid memcopying a very large returndata
        // returned by a malicious contract
        assembly {
            _success := call(
                _gas, // gas
                _target, // recipient
                _value, // ether value
                add(_calldata, 0x20), // inloc
                mload(_calldata), // inlen
                0, // outloc
                0 // outlen
            )
            // limit our copy to 256 bytes
            _toCopy := returndatasize()
            if gt(_toCopy, _maxCopy) {
                _toCopy := _maxCopy
            }
            // Store the length of the copied bytes
            mstore(_returnData, _toCopy)
            // copy the bytes from returndata[0:_toCopy]
            returndatacopy(add(_returnData, 0x20), 0, _toCopy)
        }
        return (_success, _returnData);
    }

    /// @dev Must be memory since we had to decode it
    function _openCdpCallback(bytes memory data) internal {
        OpenCdpOperation memory flData = abi.decode(data, (OpenCdpOperation));

        /**
         * Open CDP and Emit event
         */
        bytes32 _cdpId = borrowerOperations.openCdp(
            flData.eBTCToMint,
            flData._upperHint,
            flData._lowerHint,
            flData.stETHToDeposit
        );
    }

/*
    function openCdpWithEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _ethMarginBalance,
        uint256 _stEthDepositAmount,
        PositionManagerPermit calldata _positionManagerPermit,
        TradeData calldata _tradeData,
        uint256 getId,
        uint256 setId
    ) external payable returns (bytes32 cdpId) {

    }

    function openCdpWithWstEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _wstEthMarginBalance,
        uint256 _stEthDepositAmount,
        PositionManagerPermit calldata _positionManagerPermit,
        TradeData calldata _tradeData,
        uint256 getId,
        uint256 setId
    ) external returns (bytes32 cdpId) {

    }

    function openCdpWithWrappedEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _wethMarginBalance,
        uint256 _stEthDepositAmount,
        PositionManagerPermit calldata _positionManagerPermit,
        TradeData calldata _tradeData,
        uint256 getId,
        uint256 setId
    ) external returns (bytes32 cdpId) {

    }

    function closeCdp(
        bytes32 _cdpId,
        PositionManagerPermit calldata _positionManagerPermit,
        uint256 _stEthAmount,
        TradeData calldata _tradeData,
        uint256 getId,
        uint256 setId
    ) external {

    }

    function closeCdpForWstETH(
        bytes32 _cdpId,
        PositionManagerPermit calldata _positionManagerPermit,
        uint256 _stEthAmount,
        TradeData calldata _tradeData,
        uint256 getId,
        uint256 setId
    ) external {

    }

    function adjustCdp(
        bytes32 _cdpId,
        AdjustCdpParams calldata params,
        PositionManagerPermit calldata _positionManagerPermit,
        TradeData calldata _tradeData,
        uint256 getId,
        uint256 setId
    ) external {

    }

    function adjustCdpWithEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        PositionManagerPermit calldata _positionManagerPermit,
        TradeData calldata _tradeData,
        uint256 getId,
        uint256 setId
    ) external payable {

    }
        
    function adjustCdpWithWstEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        PositionManagerPermit calldata _positionManagerPermit,
        TradeData calldata _tradeData,
        uint256 getId,
        uint256 setId
    ) external {

    }

    function adjustCdpWithWrappedEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        PositionManagerPermit calldata _positionManagerPermit,
        TradeData calldata _tradeData,
        uint256 getId,
        uint256 setId
    ) external {

    }
*/
}

contract ConnectV2BadgerZapRouter is BadgerZapRouter {
    string public constant name = "Badger-Zap-Router-v1.0";

    constructor(
        address _flashLoanReceiver, 
        address _borrowerOperations, 
        address _stETH, 
        address _ebtcToken, 
        address _sortedCdps,
        address _dex
    ) 
        BadgerZapRouter(_flashLoanReceiver, _borrowerOperations, _stETH, _ebtcToken, _sortedCdps, _dex) {

    }
}
