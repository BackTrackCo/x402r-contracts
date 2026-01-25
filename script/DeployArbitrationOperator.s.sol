// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";

/**
 * @title DeployArbitrationOperator
 * @notice Deploys the ArbitrationOperator contract for x402r/Chamba
 * @dev This script deploys the ArbitrationOperator contract with the pull model architecture.
 *      Uses 2 hook slots (BEFORE_HOOK, AFTER_HOOK) with action routing.
 *
 *      NOTE: For production deployments, prefer using ArbitrationOperatorFactory which handles
 *      deterministic addresses and reusable hooks. This script is for manual deployments.
 *
 *      Environment variables:
 *      - ESCROW_ADDRESS: Base Commerce Payments escrow contract address (required)
 *      - PROTOCOL_FEE_RECIPIENT: Address to receive protocol fees (required)
 *      - MAX_TOTAL_FEE_RATE: Maximum total fee rate in basis points (default: 5 = 0.05%)
 *      - PROTOCOL_FEE_PERCENTAGE: Protocol fee percentage 0-100 (default: 25 = 25%)
 *      - ARBITER_ADDRESS: Address of the arbiter for dispute resolution (required)
 *      - OWNER_ADDRESS: Owner of the operator contract (required)
 *      - BEFORE_HOOK: BEFORE_HOOK contract address (optional, address(0) for no-op)
 *      - AFTER_HOOK: AFTER_HOOK contract address (optional, address(0) for no-op)
 */
contract DeployArbitrationOperator is Script {
    function run() public {
        // Get addresses from environment variables
        address escrow = vm.envAddress("ESCROW_ADDRESS");
        address protocolFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        address arbiter = vm.envAddress("ARBITER_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");
        
        // Optional hook overrides
        address beforeHook = vm.envOr("BEFORE_HOOK", address(0));
        address afterHook = vm.envOr("AFTER_HOOK", address(0));

        // Get fee configuration from environment variables or use defaults
        uint256 maxTotalFeeRate = vm.envOr("MAX_TOTAL_FEE_RATE", uint256(5));
        uint256 protocolFeePercentage = vm.envOr("PROTOCOL_FEE_PERCENTAGE", uint256(25));

        vm.startBroadcast();

        console.log("=== Deploying ArbitrationOperator (Pull Model) ===");
        console.log("Escrow address:", escrow);
        console.log("Protocol fee recipient:", protocolFeeRecipient);
        console.log("Max total fee rate (basis points):", maxTotalFeeRate);
        console.log("Protocol fee percentage:", protocolFeePercentage);
        console.log("Arbiter:", arbiter);
        console.log("Owner:", owner);
        console.log("BEFORE_HOOK:", beforeHook);
        console.log("AFTER_HOOK:", afterHook);

        // Deploy ArbitrationOperator with 2 hook slots
        ArbitrationOperator operator = new ArbitrationOperator(
            escrow,
            protocolFeeRecipient,
            maxTotalFeeRate,
            protocolFeePercentage,
            arbiter,
            owner,
            beforeHook,   // BEFORE_HOOK: permission checks (routes by action)
            afterHook     // AFTER_HOOK: notifications (routes by action)
        );

        console.log("\n=== Deployment Summary ===");
        console.log("ArbitrationOperator:", address(operator));
        console.log("Owner:", operator.owner());
        console.log("Escrow:", address(operator.ESCROW()));
        console.log("Arbiter:", operator.ARBITER());
        console.log("Protocol fee recipient:", operator.protocolFeeRecipient());
        console.log("Max total fee rate:", operator.MAX_TOTAL_FEE_RATE());
        console.log("Protocol fee percentage:", operator.PROTOCOL_FEE_PERCENTAGE());
        console.log("Max arbiter fee rate:", operator.MAX_ARBITER_FEE_RATE());
        console.log("BEFORE_HOOK:", address(operator.BEFORE_HOOK()));
        console.log("AFTER_HOOK:", address(operator.AFTER_HOOK()));
        console.log("Fees enabled:", operator.feesEnabled());
        console.log("\n=== Configuration ===");
        console.log("OPERATOR_ADDRESS=", address(operator));
        console.log("\nNote: Protocol fees are disabled by default. Use setFeesEnabled(true) to enable.");

        vm.stopBroadcast();
    }
}
