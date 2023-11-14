// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IEbtcZapRouter {
    struct PositionManagerPermit {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

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

    function adjustCdp(
        bytes32 _cdpId,
        uint256 _stEthBalanceDecrease,
        uint256 _debtChange,
        bool _isDebtIncrease,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalanceIncrease,
        PositionManagerPermit memory _positionManagerPermit
        ) external;

    // function adjustCdpWithEth(
    //     bytes32 _cdpId,
    //     uint256 _stEthBalanceDecrease,
    //     uint256 _debtChange,
    //     bool _isDebtIncrease,
    //     bytes32 _upperHint,
    //     bytes32 _lowerHint,
    //     uint256 _ethBalanceIncrease,
    //     PositionManagerPermit memory _positionManagerPermit
    //     ) external payable;

    function closeCdp(
        bytes32 _cdpId,
        PositionManagerPermit memory _positionManagerPermit
    ) external;
}
