// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculator.sol";
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
        uint256 protocolFeeBps = vm.envOr("PROTOCOL_FEE_BPS", uint256(0));
        address feeRecipient = vm.envOr("FEE_RECIPIENT", msg.sender);
        address feeCalculator = vm.envOr("FEE_CALCULATOR", address(0));

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
        console.log("\n--- Deploying Modular Fee System ---");
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

        PaymentOperatorFactory.OperatorConfig memory operatorConfig = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: feeRecipient,
            feeCalculator: feeCalculator,
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

        address operatorAddress = factory.deployOperator(operatorConfig);
        PaymentOperator operator = PaymentOperator(payable(operatorAddress));

        console.log("PaymentOperator deployed:", address(operator));

        vm.stopBroadcast();

        // Summary
        console.log("\n=== TESTNET DEPLOYMENT SUCCESSFUL ===");
        console.log("Factory:", address(factory));
        console.log("Operator:", address(operator));
        console.log("ProtocolFeeConfig:", address(protocolFeeConfig));
        console.log("Escrow:", escrow);
        console.log("Owner:", owner);
        console.log("\n[TEST] Ready for testing!\n");
    }
}
