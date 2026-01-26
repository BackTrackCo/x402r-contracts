// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {AuthCaptureEscrow} from "../lib/commerce-payments/src/AuthCaptureEscrow.sol";
import {ERC3009PaymentCollector} from "../lib/commerce-payments/src/collectors/ERC3009PaymentCollector.sol";
import {
    EscrowPeriodConditionFactory
} from "../src/commerce-payments/conditions/escrow-period/EscrowPeriodConditionFactory.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {FreezePolicyFactory} from "../src/commerce-payments/conditions/escrow-period/freeze-policy/FreezePolicyFactory.sol";
import {PayerCondition} from "../src/commerce-payments/conditions/access/PayerCondition.sol";
import {ReceiverCondition} from "../src/commerce-payments/conditions/access/ReceiverCondition.sol";
import {ArbiterCondition} from "../src/commerce-payments/conditions/access/ArbiterCondition.sol";
import {AlwaysTrueCondition} from "../src/commerce-payments/conditions/access/AlwaysTrueCondition.sol";
import {RefundRequest} from "../src/commerce-payments/requests/refund/RefundRequest.sol";

/**
 * @title DeployAll
 * @notice Master deployment script for x402r contracts
 * @dev Deploys all x402r contracts in the correct order:
 *      1. AuthCaptureEscrow (Base Commerce Payments with partialVoid)
 *      2. ERC3009PaymentCollector
 *      3. EscrowPeriodConditionFactory
 *      4. ArbitrationOperatorFactory
 *      5. Condition Singletons (PayerCondition, ReceiverCondition, ArbiterCondition, AlwaysTrueCondition)
 *      6. FreezePolicyFactory (for creating freeze policy instances)
 *      7. RefundRequest
 *
 *      Note: This script deploys only the factories. Factory instances (conditions and operators)
 *      should be deployed on-demand via the SDK or by calling the factory's deploy methods directly.
 *      Hook implementations should be deployed separately as needed.
 *
 *      Environment variables:
 *      - PROTOCOL_FEE_RECIPIENT: Address to receive protocol fees (required for operator factory)
 *      - MAX_TOTAL_FEE_RATE: Maximum total fee rate in basis points (default: 5 = 0.05%)
 *      - PROTOCOL_FEE_PERCENTAGE: Protocol fee percentage 0-100 (default: 25 = 25%)
 *      - OWNER_ADDRESS: Owner of the operator factory contract (required)
 *                       Controls administrative functions: setFeesEnabled() and rescueETH()
 *
 *      Usage:
 *      forge script script/DeployAll.s.sol:DeployAll \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        -vvvv
 */
contract DeployAll is Script {
    // Known addresses (same as commerce-payments)
    address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    // Deployed contract addresses (will be populated during deployment)
    address public escrow;
    address public erc3009Collector;
    address public refundRequest;
    address public operatorFactory;
    address public conditionFactory;
    address public freezePolicyFactory;
    address public payerCondition;
    address public receiverCondition;
    address public arbiterCondition;
    address public alwaysTrueCondition;

    function run() public {
        // Get configuration from environment variables
        address protocolFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        address owner = vm.envAddress("OWNER_ADDRESS");
        uint256 maxTotalFeeRate = vm.envOr("MAX_TOTAL_FEE_RATE", uint256(5));
        uint256 protocolFeePercentage = vm.envOr("PROTOCOL_FEE_PERCENTAGE", uint256(25));

        vm.startBroadcast();

        console.log("=== Deploying x402r Contracts ===");
        console.log("Protocol fee recipient:", protocolFeeRecipient);
        console.log("Owner:", owner);
        console.log("Max total fee rate (basis points):", maxTotalFeeRate);
        console.log("Protocol fee percentage:", protocolFeePercentage);

        // Step 1: Deploy Base Commerce Payments (with partialVoid)
        console.log("\n=== Step 1: Deploying AuthCaptureEscrow ===");
        AuthCaptureEscrow authCaptureEscrow = new AuthCaptureEscrow();
        escrow = address(authCaptureEscrow);
        console.log("AuthCaptureEscrow:", escrow);

        console.log("\n=== Step 2: Deploying ERC3009PaymentCollector ===");
        ERC3009PaymentCollector collector = new ERC3009PaymentCollector(escrow, MULTICALL3);
        erc3009Collector = address(collector);
        console.log("ERC3009PaymentCollector:", erc3009Collector);

        // Step 3: Deploy EscrowPeriodConditionFactory
        console.log("\n=== Step 3: Deploying EscrowPeriodConditionFactory ===");
        EscrowPeriodConditionFactory conditionFactoryContract = new EscrowPeriodConditionFactory();
        conditionFactory = address(conditionFactoryContract);
        console.log("EscrowPeriodConditionFactory:", conditionFactory);

        // Step 4: Deploy ArbitrationOperatorFactory
        console.log("\n=== Step 4: Deploying ArbitrationOperatorFactory ===");
        ArbitrationOperatorFactory operatorFactoryContract =
            new ArbitrationOperatorFactory(escrow, protocolFeeRecipient, maxTotalFeeRate, protocolFeePercentage, owner);
        operatorFactory = address(operatorFactoryContract);
        console.log("ArbitrationOperatorFactory:", operatorFactory);

        // Step 5: Deploy Condition Singletons
        console.log("\n=== Step 5: Deploying Condition Singletons ===");
        PayerCondition payerConditionContract = new PayerCondition();
        payerCondition = address(payerConditionContract);
        console.log("PayerCondition:", payerCondition);

        ReceiverCondition receiverConditionContract = new ReceiverCondition();
        receiverCondition = address(receiverConditionContract);
        console.log("ReceiverCondition:", receiverCondition);

        ArbiterCondition arbiterConditionContract = new ArbiterCondition();
        arbiterCondition = address(arbiterConditionContract);
        console.log("ArbiterCondition:", arbiterCondition);

        AlwaysTrueCondition alwaysTrueConditionContract = new AlwaysTrueCondition();
        alwaysTrueCondition = address(alwaysTrueConditionContract);
        console.log("AlwaysTrueCondition:", alwaysTrueCondition);

        // Step 6: Deploy FreezePolicyFactory
        console.log("\n=== Step 6: Deploying FreezePolicyFactory ===");
        FreezePolicyFactory freezePolicyFactoryContract = new FreezePolicyFactory();
        freezePolicyFactory = address(freezePolicyFactoryContract);
        console.log("FreezePolicyFactory:", freezePolicyFactory);

        // Step 7: Deploy RefundRequest
        console.log("\n=== Step 7: Deploying RefundRequest ===");
        RefundRequest refundRequestContract = new RefundRequest();
        refundRequest = address(refundRequestContract);
        console.log("RefundRequest:", refundRequest);

        vm.stopBroadcast();

        // Print deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("AuthCaptureEscrow:", escrow);
        console.log("ERC3009PaymentCollector:", erc3009Collector);
        console.log("EscrowPeriodConditionFactory:", conditionFactory);
        console.log("ArbitrationOperatorFactory:", operatorFactory);
        console.log("PayerCondition:", payerCondition);
        console.log("ReceiverCondition:", receiverCondition);
        console.log("ArbiterCondition:", arbiterCondition);
        console.log("AlwaysTrueCondition:", alwaysTrueCondition);
        console.log("FreezePolicyFactory:", freezePolicyFactory);
        console.log("RefundRequest:", refundRequest);

        console.log("\n=== Factory Addresses ===");
        console.log("Use these factories to deploy instances on-demand via SDK or direct calls:");
        console.log("CONDITION_FACTORY_ADDRESS=", conditionFactory);
        console.log("OPERATOR_FACTORY_ADDRESS=", operatorFactory);
        console.log("FREEZE_POLICY_FACTORY_ADDRESS=", freezePolicyFactory);
        console.log("\n=== Condition Singleton Addresses ===");
        console.log("PAYER_CONDITION_ADDRESS=", payerCondition);
        console.log("RECEIVER_CONDITION_ADDRESS=", receiverCondition);
        console.log("ARBITER_CONDITION_ADDRESS=", arbiterCondition);
        console.log("ALWAYS_TRUE_CONDITION_ADDRESS=", alwaysTrueCondition);
        console.log("\n=== Other Contract Addresses ===");
        console.log("ESCROW_ADDRESS=", escrow);
        console.log("ERC3009_COLLECTOR_ADDRESS=", erc3009Collector);
        console.log("REFUND_REQUEST_ADDRESS=", refundRequest);
    }
}
