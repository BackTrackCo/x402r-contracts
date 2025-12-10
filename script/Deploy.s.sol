// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {EscrowFactory} from "../src/simple/main/factory/EscrowFactory.sol";
import {DepositRelay} from "../src/simple/main/x402/DepositRelay.sol";
import {FactoryRelay} from "../src/simple/main/x402/FactoryRelay.sol";

contract DeployScript is Script {
    function run() external {
        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Get addresses from environment variables
        // For Base Sepolia, you need to provide these addresses
        // Check Aave v3 testnet deployments: https://github.com/aave/aave-v3-deployments
        address usdc = vm.envOr("USDC_ADDRESS", address(0x036CbD53842c5426634e7929541eC2318f3dCF7e));
        address aUsdc = vm.envOr("AUSDC_ADDRESS", address(0x5B8B23A19E0f3c3FaA780Aa8B736bF6e8F3153B9));
        address pool = vm.envOr("AAVE_POOL_ADDRESS", address(0x0a1d576f3eFeF75b330424287a95A366e8281D80));

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying contracts to Base Sepolia...");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("USDC Address:", usdc);
        console.log("aUSDC Address:", aUsdc);
        console.log("Aave Pool Address:", pool);

        // Deploy FactoryRelay (no constructor params)
        console.log("\nDeploying FactoryRelay...");
        FactoryRelay factoryRelay = new FactoryRelay();
        console.log("FactoryRelay deployed at:", address(factoryRelay));

        // Deploy DepositRelay (requires USDC address)
        console.log("\nDeploying DepositRelay...");
        DepositRelay depositRelay = new DepositRelay(usdc);
        console.log("DepositRelay deployed at:", address(depositRelay));

        // Deploy EscrowFactory (requires USDC, aUSDC, pool)
        // Note: Merchants choose their own arbiter when registering
        console.log("\nDeploying EscrowFactory...");
        EscrowFactory escrowFactory = new EscrowFactory(
            usdc,
            aUsdc,
            pool
        );
        console.log("EscrowFactory deployed at:", address(escrowFactory));

        console.log("\n=== Deployment Summary ===");
        console.log("FactoryRelay:", address(factoryRelay));
        console.log("DepositRelay:", address(depositRelay));
        console.log("EscrowFactory:", address(escrowFactory));

        vm.stopBroadcast();
    }
}

