// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PaymentOperator} from "../src/operator/arbitration/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title DeployTestnet
 * @notice Testnet deployment script - allows EOA owner for testing
 * @dev Does NOT validate owner is multisig - for testnet/development only
 *
 * Usage:
 *   forge script script/DeployTestnet.s.sol --rpc-url base-sepolia --broadcast
 *
 * Environment Variables (optional - uses defaults if not set):
 *   OWNER_ADDRESS - Owner address (defaults to deployer)
 *   ... (same as DeployProduction.s.sol)
 */
contract DeployTestnet is Script {
    function run() external {
        // Load configuration from environment (with defaults for testnet)
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);
        address escrow = vm.envOr("ESCROW_ADDRESS", address(0));
        address protocolFeeRecipient = vm.envOr("PROTOCOL_FEE_RECIPIENT", msg.sender);
        uint256 maxTotalFeeRate = vm.envOr("MAX_TOTAL_FEE_RATE", uint256(50)); // 0.5%
        uint256 protocolFeePercentage = vm.envOr("PROTOCOL_FEE_PERCENTAGE", uint256(25)); // 25%
        address feeRecipient = vm.envOr("FEE_RECIPIENT", msg.sender);

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

        // Build condition configuration (all address(0) for simple testnet setup)
        PaymentOperator.ConditionConfig memory conditionConfig = PaymentOperator.ConditionConfig({
            authorizeCondition: vm.envOr("AUTHORIZE_CONDITION", address(0)),
            authorizeRecorder: vm.envOr("AUTHORIZE_RECORDER", address(0)),
            chargeCondition: vm.envOr("CHARGE_CONDITION", address(0)),
            chargeRecorder: vm.envOr("CHARGE_RECORDER", address(0)),
            releaseCondition: vm.envOr("RELEASE_CONDITION", address(0)),
            releaseRecorder: vm.envOr("RELEASE_RECORDER", address(0)),
            refundInEscrowCondition: vm.envOr("REFUND_IN_ESCROW_CONDITION", address(0)),
            refundInEscrowRecorder: vm.envOr("REFUND_IN_ESCROW_RECORDER", address(0)),
            refundPostEscrowCondition: vm.envOr("REFUND_POST_ESCROW_CONDITION", address(0)),
            refundPostEscrowRecorder: vm.envOr("REFUND_POST_ESCROW_RECORDER", address(0))
        });

        // Deploy
        console.log("\n--- Deploying PaymentOperatorFactory ---");
        vm.startBroadcast();

        PaymentOperatorFactory factory =
            new PaymentOperatorFactory(escrow, protocolFeeRecipient, maxTotalFeeRate, protocolFeePercentage, owner);

        console.log("Factory deployed:", address(factory));

        PaymentOperatorFactory.OperatorConfig memory operatorConfig = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: feeRecipient,
            authorizeCondition: conditionConfig.authorizeCondition,
            authorizeRecorder: conditionConfig.authorizeRecorder,
            chargeCondition: conditionConfig.chargeCondition,
            chargeRecorder: conditionConfig.chargeRecorder,
            releaseCondition: conditionConfig.releaseCondition,
            releaseRecorder: conditionConfig.releaseRecorder,
            refundInEscrowCondition: conditionConfig.refundInEscrowCondition,
            refundInEscrowRecorder: conditionConfig.refundInEscrowRecorder,
            refundPostEscrowCondition: conditionConfig.refundPostEscrowCondition,
            refundPostEscrowRecorder: conditionConfig.refundPostEscrowRecorder
        });

        address operatorAddress = factory.deployOperator(operatorConfig);
        PaymentOperator operator = PaymentOperator(payable(operatorAddress));

        console.log("PaymentOperator deployed:", address(operator));

        vm.stopBroadcast();

        // Summary
        console.log("\n=== TESTNET DEPLOYMENT SUCCESSFUL ===");
        console.log("Factory:", address(factory));
        console.log("Operator:", address(operator));
        console.log("Escrow:", escrow);
        console.log("Owner:", owner);
        console.log("\n[TEST] Ready for testing!\n");
    }
}
