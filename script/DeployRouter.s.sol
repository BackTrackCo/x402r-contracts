// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {MerchantRegistrationRouter} from "../src/simple/main/x402/MerchantRegistrationRouter.sol";

/**
 * @title DeployRouter
 * @notice Deploys the MerchantRegistrationRouter contract
 * @dev This script deploys the Router which depends on:
 *      - Factory address (DEPOSIT_RELAY_FACTORY_ADDRESS env var)
 *      - Escrow address (SHARED_ESCROW_ADDRESS env var)
 */
contract DeployRouter is Script {
    function run() public {
        // Get addresses from environment variables
        address factoryAddress = vm.envOr("DEPOSIT_RELAY_FACTORY_ADDRESS", address(0));
        require(factoryAddress != address(0), "DEPOSIT_RELAY_FACTORY_ADDRESS must be set");
        
        address escrowAddress = vm.envOr("SHARED_ESCROW_ADDRESS", address(0));
        require(escrowAddress != address(0), "SHARED_ESCROW_ADDRESS must be set");
        
        vm.startBroadcast();
        
        console.log("=== Deploying MerchantRegistrationRouter ===");
        console.log("Factory address:", factoryAddress);
        console.log("Escrow address:", escrowAddress);
        
        // Deploy MerchantRegistrationRouter
        MerchantRegistrationRouter router = new MerchantRegistrationRouter(
            factoryAddress,
            escrowAddress
        );
        
        console.log("\n=== Deployment Summary ===");
        console.log("MerchantRegistrationRouter:", address(router));
        console.log("\n=== Configuration ===");
        console.log("ROUTER_ADDRESS=", address(router));
        console.log("\nNote: Merchants should use router.registerMerchantAndDeployProxy(arbiter)");
        console.log("      instead of calling escrow and factory separately.");
        
        vm.stopBroadcast();
    }
}

