// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/ArbitrationOperator.sol";

/**
 * @title DeployArbitrationOperator
 * @notice Deploys the ArbitrationOperator contract
 * @dev This script deploys the ArbitrationOperator contract that wraps Base Commerce Payments
 *      and enforces arbiter-based refund restrictions and fee distribution.
 *      Escrow period is set at deployment (immutable per operator).
 *
 *      Environment variables:
 *      - ESCROW_ADDRESS: Base Commerce Payments escrow contract address (required)
 *      - PROTOCOL_FEE_RECIPIENT: Address to receive protocol fees (required)
 *      - MAX_TOTAL_FEE_RATE: Maximum total fee rate in basis points (default: 5 = 0.05%)
 *      - PROTOCOL_FEE_PERCENTAGE: Protocol fee percentage 0-100 (default: 25 = 25%)
 *      - ARBITER_ADDRESS: Address of the arbiter for dispute resolution (required)
 *      - OWNER_ADDRESS: Owner of the operator contract (required)
 *      - ESCROW_PERIOD: Escrow period in seconds (default: 7 days)
 */
contract DeployArbitrationOperator is Script {
    function run() public {
        // Get addresses from environment variables
        address escrow = vm.envAddress("ESCROW_ADDRESS");
        address protocolFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        address arbiter = vm.envAddress("ARBITER_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");

        // Get fee configuration from environment variables or use defaults
        // Default: 5 basis points (0.05%) total fee rate
        uint256 maxTotalFeeRate = vm.envOr("MAX_TOTAL_FEE_RATE", uint256(5));
        // Default: 25% protocol fee (arbiter gets 75%)
        uint256 protocolFeePercentage = vm.envOr("PROTOCOL_FEE_PERCENTAGE", uint256(25));
        // Default: 7 days escrow period
        uint48 escrowPeriod = uint48(vm.envOr("ESCROW_PERIOD", uint256(7 days)));

        vm.startBroadcast();

        console.log("=== Deploying ArbitrationOperator ===");
        console.log("Escrow address:", escrow);
        console.log("Protocol fee recipient:", protocolFeeRecipient);
        console.log("Max total fee rate (basis points):", maxTotalFeeRate);
        console.log("Protocol fee percentage:", protocolFeePercentage);
        console.log("Arbiter:", arbiter);
        console.log("Owner:", owner);
        console.log("Escrow period (seconds):", escrowPeriod);

        // Deploy ArbitrationOperator
        ArbitrationOperator operator = new ArbitrationOperator(
            escrow,
            protocolFeeRecipient,
            maxTotalFeeRate,
            protocolFeePercentage,
            arbiter,
            owner,
            escrowPeriod
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
        console.log("Escrow period:", operator.ESCROW_PERIOD());
        console.log("Fees enabled:", operator.feesEnabled());
        console.log("\n=== Configuration ===");
        console.log("OPERATOR_ADDRESS=", address(operator));
        console.log("\nNote: Protocol fees are disabled by default. Use setFeesEnabled(true) to enable.");

        vm.stopBroadcast();
    }
}
