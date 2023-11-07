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
        address sortedCdps;
    }

    function openCdp(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _stEthBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external;

    function openCdpWithEth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _ethBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external payable;

    function openCdpWithWeth(
        uint256 _debt,
        bytes32 _upperHint,
        bytes32 _lowerHint,
        uint256 _wethBalance,
        PositionManagerPermit memory _positionManagerPermit
    ) external;

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
    ) external;
}
