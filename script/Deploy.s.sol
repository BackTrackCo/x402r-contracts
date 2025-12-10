// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {EscrowFactory} from "../src/simple/main/factory/EscrowFactory.sol";
import {DepositRelay} from "../src/simple/main/x402/DepositRelay.sol";
import {FactoryRelay} from "../src/simple/main/x402/FactoryRelay.sol";

contract DeployScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get addresses from environment variables or use defaults
        // Base Sepolia Aave v3 addresses
        // These can be found at: https://docs.aave.com/developers/deployed-contracts/v3-testnet-addresses
        address usdc = vm.envOr("USDC_ADDRESS", address(0x036CbD53842c5426634e7929541eC2318f3dCF7e));
        address ausdc = vm.envOr("AUSDC_ADDRESS", address(0x16da4541Ad1807f4443D92db2609C28c199c358E));
        address pool = vm.envOr("POOL_ADDRESS", address(0x4CB093f226983713164a62138c3f718a9166E6E8));

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying contracts to Base Sepolia...");
        console.log("USDC address:", usdc);
        console.log("aUSDC address:", ausdc);
        console.log("Pool address:", pool);

        // Deploy EscrowFactory
        console.log("\n=== Deploying EscrowFactory ===");
        EscrowFactory factory = new EscrowFactory(
            usdc,
            ausdc,
            pool
        );
        console.log("EscrowFactory deployed at:", address(factory));

        // Deploy DepositRelay
        console.log("\n=== Deploying DepositRelay ===");
        DepositRelay depositRelay = new DepositRelay(usdc);
        console.log("DepositRelay deployed at:", address(depositRelay));

        // Deploy FactoryRelay
        console.log("\n=== Deploying FactoryRelay ===");
        FactoryRelay factoryRelay = new FactoryRelay();
        console.log("FactoryRelay deployed at:", address(factoryRelay));

        console.log("\n=== Deployment Summary ===");
        console.log("EscrowFactory:", address(factory));
        console.log("DepositRelay:", address(depositRelay));
        console.log("FactoryRelay:", address(factoryRelay));

        vm.stopBroadcast();
    }
}

