// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {DepositRelayFactory} from "../src/simple/main/x402/DepositRelayFactory.sol";

/**
 * @title DeployFactory
 * @notice Deploys the DepositRelayFactory contract
 * @dev This script deploys the Factory which depends on:
 *      - Escrow address (SHARED_ESCROW_ADDRESS env var or must be provided)
 *      - CreateX address (CREATEX_ADDRESS env var, defaults to standard Base Sepolia address)
 *      - Token address (USDC_ADDRESS env var)
 */
contract DeployFactory is Script {
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
        
        // Escrow address - REQUIRED (should be deployed first using DeployEscrow.s.sol)
        address escrowAddress = vm.envOr("SHARED_ESCROW_ADDRESS", address(0));
        require(escrowAddress != address(0), "SHARED_ESCROW_ADDRESS must be set");
        
        vm.startBroadcast();
        
        console.log("=== Deploying DepositRelayFactory ===");
        console.log("Chain ID:", chainId);
        console.log("USDC address:", usdc);
        console.log("Escrow address:", escrowAddress);
        console.log("CreateX address:", createxAddress);
        
        // Deploy DepositRelayFactory
        DepositRelayFactory depositRelayFactory = new DepositRelayFactory(
            usdc,
            escrowAddress,
            createxAddress
        );
        
        console.log("\n=== Deployment Summary ===");
        console.log("DepositRelayFactory:", address(depositRelayFactory));
        console.log("Implementation:", depositRelayFactory.IMPLEMENTATION());
        console.log("CreateX address:", depositRelayFactory.getCreateX());
        console.log("\n=== Configuration ===");
        console.log("DEPOSIT_RELAY_FACTORY_ADDRESS=", address(depositRelayFactory));
        console.log("SHARED_ESCROW_ADDRESS=", escrowAddress);
        console.log("CREATEX_ADDRESS=", createxAddress);
        console.log("\nNote: Using CREATE3 - no bytecode needed for address computation!");
        
        vm.stopBroadcast();
    }
}

