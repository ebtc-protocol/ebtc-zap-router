// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IEbtcZapRouter {
    struct PositionManagerPermit {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

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

    enum EthVariantZapOperationType {
        OpenCdp,
        AdjustCdp,
        CloseCdp
    }

    event ZapOperationEthVariant(
        bytes32 indexed cdpId,
        EthVariantZapOperationType indexed operation,
        bool isCollateralIncrease,
        address indexed collateralToken,
        uint256 collateralTokenDelta,
        uint256 stEthDelta
    );

    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external returns (bytes32 cdpId);

    function openCdpWithEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _ethBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external payable returns (bytes32 cdpId);

    function openCdpWithWrappedEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wethBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external returns (bytes32 cdpId);

    function openCdpWithWstEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wstEthBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external returns (bytes32 cdpId);

    function adjustCdp(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalanceIncrease,
        bool _useWstETHForDecrease,
        PositionManagerPermit memory _positionManagerPermit
    ) external;

    function adjustCdpWithEth(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _ethBalanceIncrease,
        bool _useWstETHForDecrease,
        PositionManagerPermit memory _positionManagerPermit
    ) external payable;

    function adjustCdpWithWrappedEth(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wethBalanceIncrease,
        bool _useWstETHForDecrease,
        PositionManagerPermit memory _positionManagerPermit
    ) external;

    function adjustCdpWithWstEth(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wstEthBalanceIncrease,
        bool _useWstETHForDecrease,
        PositionManagerPermit memory _positionManagerPermit
    ) external;

    function closeCdp(
        bytes32 _cdpId,
        PositionManagerPermit memory _positionManagerPermit
    ) external;

    function closeCdpForWstETH(
        bytes32 _cdpId,
        PositionManagerPermit memory _positionManagerPermit
    ) external;
}
