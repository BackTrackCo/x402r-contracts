// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {ArbiterationOperator} from "../src/commerce-payments/operator/ArbiterationOperator.sol";

/**
 * @title DeployArbiterationOperator
 * @notice Deploys the ArbiterationOperator contract
 * @dev This script deploys the ArbiterationOperator contract that wraps Base Commerce Payments
 *      and enforces refund delays, arbiter refund restrictions, and fee distribution.
 * 
 *      Environment variables:
 *      - ESCROW_ADDRESS: Base Commerce Payments escrow contract address (required)
 *      - PROTOCOL_FEE_RECIPIENT: Address to receive protocol fees (required)
 *      - MAX_TOTAL_FEE_RATE: Maximum total fee rate in basis points (default: 5 = 0.05%)
 *      - PROTOCOL_FEE_PERCENTAGE: Protocol fee percentage 0-100 (default: 25 = 25%)
 */
contract DeployArbiterationOperator is Script {
    function run() public {
        // Get addresses from environment variables
        address escrow = vm.envAddress("ESCROW_ADDRESS");
        address protocolFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        
        // Get fee configuration from environment variables or use defaults
        // Default: 5 basis points (0.05%) total fee rate
        uint256 maxTotalFeeRate = vm.envOr("MAX_TOTAL_FEE_RATE", uint256(5));
        // Default: 25% protocol fee (arbiter gets 75%)
        uint256 protocolFeePercentage = vm.envOr("PROTOCOL_FEE_PERCENTAGE", uint256(25));
        
        vm.startBroadcast();
        
        console.log("=== Deploying ArbiterationOperator ===");
        console.log("Escrow address:", escrow);
        console.log("Protocol fee recipient:", protocolFeeRecipient);
        console.log("Max total fee rate (basis points):", maxTotalFeeRate);
        console.log("Protocol fee percentage:", protocolFeePercentage);
        
        // Deploy ArbiterationOperator
        ArbiterationOperator operator = new ArbiterationOperator(
            escrow,
            protocolFeeRecipient,
            maxTotalFeeRate,
            protocolFeePercentage
        );
        
        console.log("\n=== Deployment Summary ===");
        console.log("ArbiterationOperator:", address(operator));
        console.log("Owner:", operator.owner());
        console.log("Escrow:", address(operator.ESCROW()));
        console.log("Protocol fee recipient:", operator.protocolFeeRecipient());
        console.log("Max total fee rate:", operator.MAX_TOTAL_FEE_RATE());
        console.log("Protocol fee percentage:", operator.PROTOCOL_FEE_PERCENTAGE());
        console.log("Max arbiter fee rate:", operator.MAX_ARBITER_FEE_RATE());
        console.log("Fees enabled:", operator.feesEnabled());
        console.log("\n=== Configuration ===");
        console.log("OPERATOR_ADDRESS=", address(operator));
        console.log("\nNote: Protocol fees are disabled by default. Use setFeesEnabled(true) to enable.");
        
        vm.stopBroadcast();
    }
}

