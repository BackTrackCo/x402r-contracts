// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {Escrow} from "../src/simple/main/escrow/Escrow.sol";
import {DepositRelayFactory} from "../src/simple/main/x402/DepositRelayFactory.sol";
import {CreateX} from "@createx/CreateX.sol";
import {ERC4626Mock} from "@openzeppelin/contracts/mocks/token/ERC4626Mock.sol";

contract DeployScript is Script {
    function run() public {
        // Get addresses from environment variables or use defaults
        // Base Sepolia USDC address
        address usdc = vm.envOr("USDC_ADDRESS", address(0x036CbD53842c5426634e7929541eC2318f3dCF7e));
        
        // CreateX address - use existing deployment or deploy new one
        // Check CreateX deployments: https://github.com/pcaversaccio/createx#createx-deployments
        // Standard CreateX address for Base Sepolia: 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed
        // If CREATEX_ADDRESS env var is set, use that; otherwise use standard Base Sepolia address
        address createxAddress = vm.envOr("CREATEX_ADDRESS", address(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed));
        
        // Version for proxy deployments (v0, v1, v2, etc.) - REQUIRED
        // Increment this when deploying a new factory with updated implementation
        uint256 version = vm.envUint("VERSION");

        // Use vm.startBroadcast() which will use the private key from --private-key flag or environment
        // If using environment variable, PRIVATE_KEY should be decimal number (no 0x prefix)
        vm.startBroadcast();

        console.log("Deploying contracts to Base Sepolia...");
        console.log("USDC address:", usdc);

        // Deploy CreateX if not provided
        if (createxAddress == address(0)) {
            console.log("\n=== Deploying CreateX ===");
            CreateX createx = new CreateX();
            createxAddress = address(createx);
            console.log("CreateX deployed at:", createxAddress);
        } else {
            console.log("\n=== Using Existing CreateX ===");
            console.log("CreateX address:", createxAddress);
        }

        // Deploy ERC4626 vault for testing
        // Note: In production, merchants would deploy their own vaults or use existing ones
        console.log("\n=== Deploying ERC4626 Vault (for testing) ===");
        ERC4626Mock vault = new ERC4626Mock(usdc);
        console.log("ERC4626 Vault deployed at:", address(vault));
        console.log("Vault asset (USDC):", vault.asset());

        // Deploy shared Escrow for refund extension
        // Note: This escrow is shared by all merchants (merchants register with it)
        console.log("\n=== Deploying Shared Escrow ===");
        Escrow sharedEscrow = new Escrow(
            address(0), // merchantPayout = 0 (shared escrow)
            address(0),  // arbiter = 0 (merchants register separately)
            usdc
        );
        console.log("Shared Escrow deployed at:", address(sharedEscrow));

        // Deploy DepositRelayFactory (now requires CreateX address and version)
        console.log("\n=== Deploying DepositRelayFactory ===");
        console.log("Factory Version:", version);
        DepositRelayFactory depositRelayFactory = new DepositRelayFactory(
            usdc,
            address(sharedEscrow),
            createxAddress,
            version
        );
        console.log("DepositRelayFactory deployed at:", address(depositRelayFactory));
        console.log("Implementation deployed at:", depositRelayFactory.IMPLEMENTATION());
        console.log("Version:", depositRelayFactory.VERSION());
        console.log("CreateX address:", depositRelayFactory.getCreateX());

        console.log("\n=== Deployment Summary ===");
        console.log("CreateX:", createxAddress);
        console.log("Shared Escrow:", address(sharedEscrow));
        console.log("DepositRelayFactory:", address(depositRelayFactory));
        console.log("Implementation:", depositRelayFactory.IMPLEMENTATION());
        console.log("Version:", depositRelayFactory.VERSION());
        console.log("\n=== Configuration for Refund Extension ===");
        console.log("DEPOSIT_RELAY_FACTORY_ADDRESS=", address(depositRelayFactory));
        console.log("SHARED_ESCROW_ADDRESS=", address(sharedEscrow));
        console.log("CREATEX_ADDRESS=", createxAddress);
        console.log("VERSION=", depositRelayFactory.VERSION());
        console.log("TEST_VAULT_ADDRESS=", address(vault));
        console.log("\nNote: Merchants must register with shared escrow:");
        console.log("      escrow.registerMerchant(arbiter, vault)");
        console.log("\nNote: For testing, merchants can use the deployed vault at:", address(vault));
        console.log("      In production, merchants should deploy their own ERC4626 vaults.");
        console.log("\nNote: Using CREATE3 - no bytecode needed for address computation!");

        vm.stopBroadcast();
    }
}

