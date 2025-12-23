// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {Escrow} from "../src/simple/main/escrow/Escrow.sol";
import {DepositRelayFactory} from "../src/simple/main/x402/DepositRelayFactory.sol";
import {CreateX} from "@createx/CreateX.sol";
import {ERC4626Mock} from "@openzeppelin/contracts/mocks/token/ERC4626Mock.sol";

contract DeployScript is Script {
    function run() public {
        uint256 chainId = block.chainid;
        
        // Get addresses from environment variables or use chain-specific defaults
        address usdc;
        address createxAddress;
        
        if (chainId == 84532) {
            // Base Sepolia
            usdc = vm.envOr("USDC_ADDRESS", address(0x036CbD53842c5426634e7929541eC2318f3dCF7e));
            createxAddress = vm.envOr("CREATEX_ADDRESS", address(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed));
        } else if (chainId == 8453) {
            // Base Mainnet
            usdc = vm.envOr("USDC_ADDRESS", address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));
            // CreateX mainnet address - check https://github.com/pcaversaccio/createx#createx-deployments
            createxAddress = vm.envOr("CREATEX_ADDRESS", address(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed));
        } else {
            // For other chains or local testing, require env vars
            usdc = vm.envAddress("USDC_ADDRESS");
            createxAddress = vm.envAddress("CREATEX_ADDRESS");
            require(usdc != address(0), "USDC_ADDRESS must be set for this chain");
            require(createxAddress != address(0), "CREATEX_ADDRESS must be set for this chain");
        }
        

        // Use vm.startBroadcast() which will use the private key from --private-key flag or environment
        // If using environment variable, PRIVATE_KEY should be decimal number (no 0x prefix)
        vm.startBroadcast();

        console.log("Deploying contracts...");
        console.log("Chain ID:", chainId);
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
        // The vault is hardcoded at deployment and used for all deposits
        console.log("\n=== Deploying Shared Escrow ===");
        Escrow sharedEscrow = new Escrow(
            usdc,
            address(vault)  // vault address (hardcoded at deployment)
        );
        console.log("Shared Escrow deployed at:", address(sharedEscrow));
        console.log("Vault (hardcoded):", address(vault));

        // Deploy DepositRelayFactory
        console.log("\n=== Deploying DepositRelayFactory ===");
        DepositRelayFactory depositRelayFactory = new DepositRelayFactory(
            usdc,
            address(sharedEscrow),
            createxAddress
        );
        console.log("DepositRelayFactory deployed at:", address(depositRelayFactory));
        console.log("Implementation deployed at:", depositRelayFactory.IMPLEMENTATION());
        console.log("CreateX address:", depositRelayFactory.getCreateX());

        console.log("\n=== Deployment Summary ===");
        console.log("CreateX:", createxAddress);
        console.log("Shared Escrow:", address(sharedEscrow));
        console.log("DepositRelayFactory:", address(depositRelayFactory));
        console.log("Implementation:", depositRelayFactory.IMPLEMENTATION());
        console.log("\n=== Configuration for Refund Extension ===");
        console.log("DEPOSIT_RELAY_FACTORY_ADDRESS=", address(depositRelayFactory));
        console.log("SHARED_ESCROW_ADDRESS=", address(sharedEscrow));
        console.log("CREATEX_ADDRESS=", createxAddress);
        console.log("TEST_VAULT_ADDRESS=", address(vault));
        console.log("\nNote: Merchants must register with shared escrow:");
        console.log("      escrow.registerMerchant(arbiter)");
        console.log("\nNote: Vault is hardcoded at deployment:", address(vault));
        console.log("\nNote: For testing, merchants can use the deployed vault at:", address(vault));
        console.log("      In production, merchants should deploy their own ERC4626 vaults.");
        console.log("\nNote: Using CREATE3 - no bytecode needed for address computation!");

        vm.stopBroadcast();
    }
}

