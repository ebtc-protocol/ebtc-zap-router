// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IEbtcZapRouterBase} from "./IEbtcZapRouterBase.sol";

interface IEbtcLeverageZapRouter is IEbtcZapRouterBase {
    struct DeploymentParams {
        address borrowerOperations;
        address activePool;
        address cdpManager;
        address ebtc;
        address stEth;
        address weth;
        address wstEth;
        address sortedCdps;
        address dex;
        address owner;
    }

    struct AdjustCdpParams {
        uint256 flashLoanAmount;
        uint256 debtChange;
        bool isDebtIncrease;
        bytes32 upperHint;
        bytes32 lowerHint;
        uint256 stEthMarginBalance;
        bool isStEthMarginIncrease;
        uint256 stEthBalanceChange;
        bool isStEthBalanceIncrease;
        bool useWstETHForDecrease;
    }

    struct TradeData {
        bytes exchangeData;
        uint256 expectedMinOut;
        bool performSwapChecks;
        uint256 approvalAmount;
    }

    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _stEthMarginAmount,
        uint256 _stEthDepositAmount,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external returns (bytes32 cdpId);

    function openCdpWithEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _ethMarginBalance,
        uint256 _stEthDepositAmount,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external payable returns (bytes32 cdpId);

    function openCdpWithWstEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _wstEthMarginBalance,
        uint256 _stEthDepositAmount,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external returns (bytes32 cdpId);

    function openCdpWithWrappedEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _wethMarginBalance,
        uint256 _stEthDepositAmount,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external returns (bytes32 cdpId);

    function closeCdp(
        bytes32 _cdpId,
        bytes calldata _positionManagerPermit,
        uint256 _stEthAmount,
        TradeData calldata _tradeData
    ) external;

    function closeCdpForWstETH(
        bytes32 _cdpId,
        bytes calldata _positionManagerPermit,
        uint256 _stEthAmount,
        TradeData calldata _tradeData
    ) external;

    function adjustCdp(
        bytes32 _cdpId,
        AdjustCdpParams calldata params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external;

    function adjustCdpWithEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external payable;
        
    function adjustCdpWithWstEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external;

    function adjustCdpWithWrappedEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        bytes calldata _positionManagerPermit,
        TradeData calldata _tradeData
    ) external;
}
