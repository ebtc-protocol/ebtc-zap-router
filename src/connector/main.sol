pragma solidity 0.8.17;

import "./events.sol";
import "./helpers.sol";
import {LeverageZapRouterBase} from "../LeverageZapRouterBase.sol";
import {IEbtcLeverageZapRouter} from "../interface/IEbtcLeverageZapRouter.sol";

abstract contract BadgerZapRouter is Helpers, Events, LeverageZapRouterBase {
    constructor(
        IEbtcLeverageZapRouter.DeploymentParams memory params
    ) LeverageZapRouterBase(params) {

    }

    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _stEthMarginAmount,
        uint256 _stEthDepositAmount,
        PositionManagerPermit calldata _positionManagerPermit,
        TradeData calldata _tradeData,
        uint256 getId,
        uint256 setId
    ) external returns (bytes32 cdpId) {
        // TODO: figure out where to do these approvals
        ebtcToken.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(borrowerOperations), type(uint256).max);
        stETH.approve(address(activePool), type(uint256).max);

        uint256 _collVal = _transferInitialStETHFromCaller(_stEthMarginAmount);

        cdpId = _openCdp(
            _debt,
            _upperHint,
            _lowerHint,
            _stEthLoanAmount,
            0, // _stEthMarginAmount transferred above
            _stEthDepositAmount,
            _positionManagerPermit,
            _tradeData
        );

        emit ZapOperationEthVariant(
            cdpId,
            EthVariantZapOperationType.OpenCdp,
            true,
            address(stEth),
            _stEthMarginAmount,
            _collVal,
            msg.sender
        );
    }

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
}

contract ConnectV2BadgerZapRouter is BadgerZapRouter {
    string public constant name = "Badger-Zap-Router-v1.0";

    constructor(
        IEbtcLeverageZapRouter.DeploymentParams memory params
    ) BadgerZapRouter(params) {

    }
}
