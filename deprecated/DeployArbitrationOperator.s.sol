// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";

/**
 * @title DeployArbitrationOperator
 * @notice Deploys the ArbitrationOperator contract for x402r/Chamba
 * @dev This script deploys the ArbitrationOperator contract with the condition combinator architecture.
 *      Uses 10 slots: 5 conditions (before checks) + 5 recorders (after state updates).
 *
 *      NOTE: For production deployments, prefer using ArbitrationOperatorFactory which handles
 *      deterministic addresses and reusable conditions. This script is for manual deployments.
 *
 *      Environment variables:
 *      - ESCROW_ADDRESS: Base Commerce Payments escrow contract address (required)
 *      - PROTOCOL_FEE_RECIPIENT: Address to receive protocol fees (required)
 *      - MAX_TOTAL_FEE_RATE: Maximum total fee rate in basis points (default: 5 = 0.05%)
 *      - PROTOCOL_FEE_PERCENTAGE: Protocol fee percentage 0-100 (default: 25 = 25%)
 *      - ARBITER_ADDRESS: Address of the arbiter for dispute resolution (required)
 *      - OWNER_ADDRESS: Owner of the operator contract (required)
 *      - AUTHORIZE_CONDITION: Condition for authorize (optional, address(0) = allow all)
 *      - AUTHORIZE_RECORDER: Recorder for authorize (optional, address(0) = no-op)
 *      - CHARGE_CONDITION: Condition for charge (optional, address(0) = allow all)
 *      - CHARGE_RECORDER: Recorder for charge (optional, address(0) = no-op)
 *      - RELEASE_CONDITION: Condition for release (optional, address(0) = allow all)
 *      - RELEASE_RECORDER: Recorder for release (optional, address(0) = no-op)
 *      - REFUND_IN_ESCROW_CONDITION: Condition for refund in escrow (optional, address(0) = allow all)
 *      - REFUND_IN_ESCROW_RECORDER: Recorder for refund in escrow (optional, address(0) = no-op)
 *      - REFUND_POST_ESCROW_CONDITION: Condition for refund post escrow (optional, address(0) = allow all)
 *      - REFUND_POST_ESCROW_RECORDER: Recorder for refund post escrow (optional, address(0) = no-op)
 */
contract DeployArbitrationOperator is Script {
    function run() public {
        // Get addresses from environment variables
        address escrow = vm.envAddress("ESCROW_ADDRESS");
        address protocolFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        address arbiter = vm.envAddress("ARBITER_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");

        // Optional condition/recorder overrides
        address authorizeCondition = vm.envOr("AUTHORIZE_CONDITION", address(0));
        address authorizeRecorder = vm.envOr("AUTHORIZE_RECORDER", address(0));
        address chargeCondition = vm.envOr("CHARGE_CONDITION", address(0));
        address chargeRecorder = vm.envOr("CHARGE_RECORDER", address(0));
        address releaseCondition = vm.envOr("RELEASE_CONDITION", address(0));
        address releaseRecorder = vm.envOr("RELEASE_RECORDER", address(0));
        address refundInEscrowCondition = vm.envOr("REFUND_IN_ESCROW_CONDITION", address(0));
        address refundInEscrowRecorder = vm.envOr("REFUND_IN_ESCROW_RECORDER", address(0));
        address refundPostEscrowCondition = vm.envOr("REFUND_POST_ESCROW_CONDITION", address(0));
        address refundPostEscrowRecorder = vm.envOr("REFUND_POST_ESCROW_RECORDER", address(0));

        // Get fee configuration from environment variables or use defaults
        uint256 maxTotalFeeRate = vm.envOr("MAX_TOTAL_FEE_RATE", uint256(5));
        uint256 protocolFeePercentage = vm.envOr("PROTOCOL_FEE_PERCENTAGE", uint256(25));

        vm.startBroadcast();

        console.log("=== Deploying ArbitrationOperator (Condition Combinator Architecture) ===");
        console.log("Escrow address:", escrow);
        console.log("Protocol fee recipient:", protocolFeeRecipient);
        console.log("Max total fee rate (basis points):", maxTotalFeeRate);
        console.log("Protocol fee percentage:", protocolFeePercentage);
        console.log("Arbiter:", arbiter);
        console.log("Owner:", owner);
        console.log("Authorize Condition:", authorizeCondition);
        console.log("Authorize Recorder:", authorizeRecorder);
        console.log("Release Condition:", releaseCondition);
        console.log("Release Recorder:", releaseRecorder);

        // Deploy ArbitrationOperator with 10 condition/recorder slots
        ArbitrationOperator.ConditionConfig memory conditions = ArbitrationOperator.ConditionConfig({
            authorizeCondition: authorizeCondition,
            authorizeRecorder: authorizeRecorder,
            chargeCondition: chargeCondition,
            chargeRecorder: chargeRecorder,
            releaseCondition: releaseCondition,
            releaseRecorder: releaseRecorder,
            refundInEscrowCondition: refundInEscrowCondition,
            refundInEscrowRecorder: refundInEscrowRecorder,
            refundPostEscrowCondition: refundPostEscrowCondition,
            refundPostEscrowRecorder: refundPostEscrowRecorder
        });
        ArbitrationOperator operator = new ArbitrationOperator(
            escrow, protocolFeeRecipient, maxTotalFeeRate, protocolFeePercentage, arbiter, owner, conditions
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
        console.log("Authorize Condition:", address(operator.AUTHORIZE_CONDITION()));
        console.log("Release Condition:", address(operator.RELEASE_CONDITION()));
        console.log("Fees enabled:", operator.feesEnabled());
        console.log("\n=== Configuration ===");
        console.log("OPERATOR_ADDRESS=", address(operator));
        console.log("\nNote: Protocol fees are disabled by default. Use setFeesEnabled(true) to enable.");

        vm.stopBroadcast();
    }
}
