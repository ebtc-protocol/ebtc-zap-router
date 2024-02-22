// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IEbtcZapRouterBase {
    struct PositionManagerPermit {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    enum EthVariantZapOperationType {
        OpenCdp,
        CloseCdp,
        AdjustCdp
    }

    event ZapOperationEthVariant(
        bytes32 indexed cdpId,
        EthVariantZapOperationType indexed operation,
        bool isCollateralIncrease,
        address indexed collateralToken,
        uint256 collateralTokenDelta,
        uint256 stEthDelta,
        address cdpOwner
    );
}
