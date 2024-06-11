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
        uint256 zapFeeBPS;
        address zapFeeReceiver;
    }

    struct AdjustCdpParams {
        /// @notice Flash loan amount used for the operation. The operation flash borrows stETH if isDebtIncrease is true and eBTC if isDebtIncrease is false
        uint256 flashLoanAmount;
        /// @notice The total eBTC debt amount withdrawn or repaid for the specified Cdp
        uint256 debtChange;
        /// @notice The flag (true or false) to indicate whether this is a eBTC token withdrawal (debt increase) or a repayment (debt reduce)
        bool isDebtIncrease;
        /// @notice The expected CdpId of neighboring higher ICR within SortedCdps, could be simply bytes32(0)
        bytes32 upperHint;
        /// @notice The expected CdpId of neighboring lower ICR within SortedCdps, could be simply bytes32(0)
        bytes32 lowerHint;
        /// @notice The amount of margin deposit/withdrawal depending on isStEthMarginIncrease
        uint256 stEthMarginBalance;
        /// @notice Set to true if stEthMarginBalance is used to increase total margin, false if stEthMarginBalance is used to decrease total margin
        bool isStEthMarginIncrease;
        /// @notice Total stETH balance change for the operation
        uint256 stEthBalanceChange;
        /// @notice Set to true if stEthBalanceChange is used to increase total collateral and false if stEthBalanceChange is used to decrease total collateral
        bool isStEthBalanceIncrease;
        /// @notice Indicator whether withdrawn collateral is original(stETH) or wrapped version(WstETH)
        bool useWstETHForDecrease;
    }

    struct TradeData {
        bytes exchangeData;
        uint256 expectedMinOut;
        bool performSwapChecks;
        uint256 approvalAmount;
        uint256 collValidationBufferBPS;
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
        TradeData calldata _tradeData
    ) external;

    function closeCdpForWstETH(
        bytes32 _cdpId,
        bytes calldata _positionManagerPermit,
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
