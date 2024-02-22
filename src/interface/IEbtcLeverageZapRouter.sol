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
        address priceFeed;
        address dex;
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

    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _stEthMarginAmount,
        uint256 _stEthDepositAmount,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) external returns (bytes32 cdpId);

    function openCdpWithEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _ethMarginBalance,
        uint256 _stEthDepositAmount,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) external payable returns (bytes32 cdpId);

    function openCdpWithWstEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _wstEthMarginBalance,
        uint256 _stEthDepositAmount,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) external returns (bytes32 cdpId);

    function openCdpWithWrappedEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthLoanAmount,
        uint256 _wethMarginBalance,
        uint256 _stEthDepositAmount,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) external returns (bytes32 cdpId);

    function closeCdp(
        bytes32 _cdpId,
        PositionManagerPermit calldata _positionManagerPermit,
        uint256 _stEthAmount,
        bytes calldata _exchangeData
    ) external;

    function closeCdpForWstETH(
        bytes32 _cdpId,
        PositionManagerPermit calldata _positionManagerPermit,
        uint256 _stEthAmount,
        bytes calldata _exchangeData
    ) external;

    function adjustCdp(
        bytes32 _cdpId,
        AdjustCdpParams calldata params,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) external;

    function adjustCdpWithEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) external payable;
        
    function adjustCdpWithWstEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) external;

    function adjustCdpWithWrappedEth(
        bytes32 _cdpId,
        AdjustCdpParams memory params,
        PositionManagerPermit calldata _positionManagerPermit,
        bytes calldata _exchangeData
    ) external;
}
