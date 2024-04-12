// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {EbtcLeverageZapRouter} from "../src/EbtcLeverageZapRouter.sol";
import {ZapRouterBaseInvariants} from "./ZapRouterBaseInvariants.sol";
import {IERC3156FlashLender} from "@ebtc/contracts/Interfaces/IERC3156FlashLender.sol";
import {IERC20} from "@ebtc/contracts/Dependencies/IERC20.sol";
import {Mock1Inch} from "@ebtc/contracts/TestContracts/Mock1Inch.sol";
import {IBorrowerOperations, IPositionManagers} from "@ebtc/contracts/LeverageMacroBase.sol";
import {BorrowerOperations} from "@ebtc/contracts/BorrowerOperations.sol";
import {ICdpManagerData} from "@ebtc/contracts/Interfaces/ICdpManager.sol";
import {IPriceFeed} from "@ebtc/contracts/Interfaces/IPriceFeed.sol";
import {IEbtcZapRouter} from "../src/interface/IEbtcZapRouter.sol";
import {IEbtcLeverageZapRouter, IEbtcLeverageZapRouterBase} from "../src/interface/IEbtcLeverageZapRouter.sol";
import {IEbtcZapRouterBase} from "../src/interface/IEbtcZapRouterBase.sol";
import {ConnectorV2BadgerZapRouter} from "../src/connector/main.sol";
import {IDSAAccount} from "../src/interface/IDSAAccount.sol";

contract DeFiSaverForkTests is Test {

}