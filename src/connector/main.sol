pragma solidity 0.8.17;

import "./events.sol";
import "./helpers.sol";
import {TokenInterface} from "../common/interfaces.sol";
import {Stores} from "../common/stores.sol";
import {LeverageZapRouterBase} from "../LeverageZapRouterBase.sol";
import {IEbtcLeverageZapRouter} from "../interface/IEbtcLeverageZapRouter.sol";
import {IBorrowerOperations, IPositionManagers} from "@ebtc/contracts/LeverageMacroBase.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import "@ebtc/contracts/Dependencies/SafeERC20.sol";
import "@ebtc/contracts/Interfaces/ISortedCdps.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManagerData.sol";
import {IPositionManagers} from "@ebtc/contracts/Interfaces/IPositionManagers.sol";

abstract contract BadgerZapRouter is Helpers, Events, Stores {
    using SafeERC20 for IERC20;

    IEbtcLeverageZapRouter public immutable zapRouter;
    IBorrowerOperations public immutable borrowerOperations;
    IERC20 public immutable stETH;

    constructor(
        address _zapRouter, 
        address _borrowerOperations,
        address _stETH
    ) {
        zapRouter = IEbtcLeverageZapRouter(_zapRouter);
        borrowerOperations = IBorrowerOperations(_borrowerOperations);
        stETH = IERC20(_stETH);
    }

    function setPositionManagerApproval() external {
        borrowerOperations.setPositionManagerApproval(
            address(zapRouter), 
            IPositionManagers.PositionManagerApproval.OneTime
        );
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
        stETH.approve(address(zapRouter), _stEthDepositAmount);

        bytes32 cdpId = zapRouter.openCdp(
            _debt, 
            _upperHint, 
            _lowerHint, 
            _stEthLoanAmount, 
            _stEthMarginAmount, 
            _stEthDepositAmount, 
            "", // PM approval
            _tradeData
        );

        setUint(setId, uint256(cdpId));

        stETH.approve(address(zapRouter), 0);

        /// TODO: set eventName/eventParam properly
    }

    function closeCdp(
        bytes32 _cdpId,
        uint256 _stEthAmount,
        IEbtcLeverageZapRouter.TradeData calldata _tradeData,
        uint256 getId,
        uint256 setId
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        _cdpId = bytes32(getUint(getId, uint256(_cdpId)));

        zapRouter.closeCdp(
            _cdpId,
            "", // PM approval
            _stEthAmount,
            _tradeData
        );

        setUint(setId, uint256(_cdpId));
        
        /// TODO: set eventName/eventParam properly
    }

    function revokePositionManagerApproval() external {
        borrowerOperations.revokePositionManagerApproval(address(zapRouter));
    }
}

contract ConnectorV2BadgerZapRouter is BadgerZapRouter {
    string public constant name = "Badger-Zap-Router-v1.0";

    constructor(
        address _zapRouter, 
        address _borrowerOperations,
        address _stETH
    ) BadgerZapRouter(_zapRouter, _borrowerOperations, _stETH) { }
}
