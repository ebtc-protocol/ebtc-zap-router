// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/EbtcZapRouter.sol";

contract DeployEbtcZapRouter is Script {

    /**
        "0xE37EEb92F541bB2bc75d0811c29F07B92DF1F64b",
        "0x61a23FD46959eF15F8B55aa22b0F7Ad957D19AAA",
        "0x97BA9AA7B7DC74f7a74864A62c4fF93b2b22f015",
        "0x0b3e07D082F07d6a8Dba3a6f6aCf32ae1ed16Ea4",
        "0x3CABDD1dF8aDdd87DA26a24ccD292f64b6065f2B",
        "0x4819558026d1bAe3ab4B6DE203a0483E8F23E047",
        "0xA967Ba66Fb284EC18bbe59f65bcf42dD11BA8128"
     */
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Define the arguments for your constructor
        IERC20 wstEth = IERC20(0xE37EEb92F541bB2bc75d0811c29F07B92DF1F64b);
        IERC20 wEth = IERC20(0x61a23FD46959eF15F8B55aa22b0F7Ad957D19AAA);
        IStETH stEth = IStETH(0x97BA9AA7B7DC74f7a74864A62c4fF93b2b22f015);
        IERC20 ebtc = IERC20(0x0b3e07D082F07d6a8Dba3a6f6aCf32ae1ed16Ea4);
        IBorrowerOperations borrowerOperations = IBorrowerOperations(0x3CABDD1dF8aDdd87DA26a24ccD292f64b6065f2B);
        ICdpManager cdpManager = ICdpManager(0x4819558026d1bAe3ab4B6DE203a0483E8F23E047);
        address owner = 0xA967Ba66Fb284EC18bbe59f65bcf42dD11BA8128;

        // Deploy the contract
        EbtcZapRouter ebtcZapRouter = new EbtcZapRouter(wstEth, wEth, stEth, ebtc, borrowerOperations, cdpManager, owner);

        vm.stopBroadcast();
    }
}