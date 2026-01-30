// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title DeployTestnet
 * @notice Testnet deployment script - deploys factory only
 * @dev Does NOT validate owner is multisig - for testnet/development only
 *      Operators are deployed on-demand via factory.deployOperator()
 *
 * Usage:
 *   forge script script/DeployTestnet.s.sol --rpc-url base-sepolia --broadcast --verify
 *
 * Environment Variables (optional - uses defaults if not set):
 *   OWNER_ADDRESS - Owner address (defaults to deployer)
 *   ESCROW_ADDRESS - Escrow address (deploys new one if not set)
 *   PROTOCOL_FEE_RECIPIENT - Protocol fee recipient (defaults to deployer)
 *   PROTOCOL_FEE_BPS - Protocol fee in basis points (defaults to 0)
 */
contract DeployTestnet is Script {
    function run() external {
        // Load configuration from environment (with defaults for testnet)
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);
        address escrow = vm.envOr("ESCROW_ADDRESS", address(0));
        address protocolFeeRecipient = vm.envOr("PROTOCOL_FEE_RECIPIENT", msg.sender);
        uint256 protocolFeeBps = vm.envOr("PROTOCOL_FEE_BPS", uint256(0));

        console.log("\n=== TESTNET DEPLOYMENT ===");
        console.log("[TEST] EOA owner allowed for testing");
        console.log("Network:", block.chainid);
        console.log("Deployer:", msg.sender);
        console.log("Owner:", owner);

        // Deploy dependencies if needed
        if (escrow == address(0)) {
            console.log("\n--- Deploying AuthCaptureEscrow (testnet) ---");
            vm.startBroadcast();
            AuthCaptureEscrow escrowContract = new AuthCaptureEscrow();
            escrow = address(escrowContract);
            console.log("Escrow deployed:", escrow);
            vm.stopBroadcast();
        }

        // Deploy
        console.log("\n--- Deploying Protocol Infrastructure ---");
        vm.startBroadcast();

        // Deploy protocol fee calculator (if > 0 bps)
        address calculatorAddr = address(0);
        if (protocolFeeBps > 0) {
            StaticFeeCalculator calculator = new StaticFeeCalculator(protocolFeeBps);
            calculatorAddr = address(calculator);
            console.log("StaticFeeCalculator:", calculatorAddr);
        }

        // Deploy ProtocolFeeConfig
        ProtocolFeeConfig protocolFeeConfig = new ProtocolFeeConfig(calculatorAddr, protocolFeeRecipient, owner);
        console.log("ProtocolFeeConfig:", address(protocolFeeConfig));

        // Deploy factory
        PaymentOperatorFactory factory = new PaymentOperatorFactory(escrow, address(protocolFeeConfig));
        console.log("Factory deployed:", address(factory));

        vm.stopBroadcast();

        // Summary
        console.log("\n=== TESTNET DEPLOYMENT SUCCESSFUL ===");
        console.log("Escrow:", escrow);
        console.log("ProtocolFeeConfig:", address(protocolFeeConfig));
        console.log("Factory:", address(factory));
        console.log("Owner:", owner);
        console.log("\nOperators deployed on-demand via factory.deployOperator()");
        console.log("\n[TEST] Ready for testing!\n");
    }
}
