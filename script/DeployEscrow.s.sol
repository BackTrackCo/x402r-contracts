// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {Escrow} from "../src/simple/main/escrow/Escrow.sol";

/**
 * @title DeployEscrow
 * @notice Deploys the shared Escrow contract independently
 * @dev This script can be run separately to deploy just the Escrow contract.
 *      The Escrow is independent and doesn't require other contracts to be deployed first.
 */
contract DeployEscrow is Script {
    function run() public {
        // Get addresses from environment variables or use defaults
        // Base Sepolia USDC address
        address usdc = vm.envOr("USDC_ADDRESS", address(0x036CbD53842c5426634e7929541eC2318f3dCF7e));
        
        vm.startBroadcast();
        
        console.log("=== Deploying Shared Escrow ===");
        console.log("USDC address:", usdc);
        
        // Deploy shared Escrow for refund extension
        // Note: This escrow is shared by all merchants (merchants register with it)
        Escrow sharedEscrow = new Escrow(
            address(0), // merchantPayout = 0 (shared escrow)
            address(0),  // arbiter = 0 (merchants register separately)
            usdc
        );
        
        console.log("\n=== Deployment Summary ===");
        console.log("Shared Escrow:", address(sharedEscrow));
        console.log("\n=== Configuration ===");
        console.log("SHARED_ESCROW_ADDRESS=", address(sharedEscrow));
        console.log("\nNote: Merchants must register with shared escrow:");
        console.log("      escrow.registerMerchant(arbiter, vault)");
        
        vm.stopBroadcast();
    }
}

