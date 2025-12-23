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
        uint256 chainId = block.chainid;
        
        // Get addresses from environment variables or use chain-specific defaults
        address usdc;
        address vault;
        
        if (chainId == 84532) {
            // Base Sepolia
            usdc = vm.envOr("USDC_ADDRESS", address(0x036CbD53842c5426634e7929541eC2318f3dCF7e));
            vault = vm.envOr("VAULT_ADDRESS", address(0xdA2502536e0E004b0AaAe30BDFd64902EA1b8849)); // Test vault
        } else if (chainId == 8453) {
            // Base Mainnet
            usdc = vm.envOr("USDC_ADDRESS", address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));
            vault = vm.envOr("VAULT_ADDRESS", address(0x7BfA7C4f149E7415b73bdeDfe609237e29CBF34A)); // Mainnet vault
        } else {
            // For other chains or local testing, require env vars
            usdc = vm.envAddress("USDC_ADDRESS");
            vault = vm.envAddress("VAULT_ADDRESS");
            require(usdc != address(0), "USDC_ADDRESS must be set for this chain");
            require(vault != address(0), "VAULT_ADDRESS must be set for this chain");
        }
        
        vm.startBroadcast();
        
        console.log("=== Deploying Shared Escrow ===");
        console.log("Chain ID:", chainId);
        console.log("USDC address:", usdc);
        console.log("Vault address:", vault);
        
        // Deploy shared Escrow for refund extension
        // Note: This escrow is shared by all merchants (merchants register with it)
        // The vault is hardcoded at deployment and used for all deposits
        Escrow sharedEscrow = new Escrow(
            usdc,
            vault        // vault address (hardcoded at deployment)
        );
        
        console.log("\n=== Deployment Summary ===");
        console.log("Shared Escrow:", address(sharedEscrow));
        console.log("\n=== Configuration ===");
        console.log("SHARED_ESCROW_ADDRESS=", address(sharedEscrow));
        console.log("\nNote: Merchants must register with shared escrow:");
        console.log("      escrow.registerMerchant(arbiter)");
        console.log("\nNote: Vault is hardcoded at deployment:", vault);
        
        vm.stopBroadcast();
    }
}

