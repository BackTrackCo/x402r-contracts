// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {ERC4626Mock} from "@openzeppelin/contracts/mocks/token/ERC4626Mock.sol";

/**
 * @title DeployVault
 * @notice Deploys an example ERC4626 vault for testing purposes
 * @dev This script deploys a mock ERC4626 vault that can be used for testing.
 *      In production, merchants should deploy their own ERC4626 vaults or use existing ones.
 *      This vault is independent and doesn't require other contracts to be deployed first.
 */
contract DeployVault is Script {
    function run() public {
        // Get addresses from environment variables or use defaults
        // Base Sepolia USDC address
        address usdc = vm.envOr("USDC_ADDRESS", address(0x036CbD53842c5426634e7929541eC2318f3dCF7e));
        
        vm.startBroadcast();
        
        console.log("=== Deploying ERC4626 Vault (for testing) ===");
        console.log("USDC address:", usdc);
        
        // Deploy ERC4626 vault for testing
        // Note: In production, merchants would deploy their own vaults or use existing ones
        ERC4626Mock vault = new ERC4626Mock(usdc);
        
        console.log("\n=== Deployment Summary ===");
        console.log("ERC4626 Vault:", address(vault));
        console.log("Vault asset (USDC):", vault.asset());
        console.log("\n=== Configuration ===");
        console.log("TEST_VAULT_ADDRESS=", address(vault));
        console.log("\nNote: This is a test vault. In production, merchants should deploy their own ERC4626 vaults.");
        
        vm.stopBroadcast();
    }
}

