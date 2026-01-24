// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {AuthCaptureEscrow} from "../lib/commerce-payments/src/AuthCaptureEscrow.sol";
import {ERC3009PaymentCollector} from "../lib/commerce-payments/src/collectors/ERC3009PaymentCollector.sol";
import {EscrowPeriodConditionFactory} from "../src/commerce-payments/release-conditions/escrow-period/EscrowPeriodConditionFactory.sol";
import {ArbitrationOperatorFactory} from "../src/commerce-payments/operator/ArbitrationOperatorFactory.sol";
import {RefundRequest} from "../src/commerce-payments/requests/refund/RefundRequest.sol";

/**
 * @title DeployAll
 * @notice Master deployment script for x402r contracts
 * @dev Deploys all x402r contracts in the correct order:
 *      1. AuthCaptureEscrow (Base Commerce Payments with partialVoid)
 *      2. ERC3009PaymentCollector
 *      3. EscrowPeriodConditionFactory and condition instance
 *      4. ArbitrationOperatorFactory and operator instance
 *      5. RefundRequest
 *
 *      Environment variables:
 *      - PROTOCOL_FEE_RECIPIENT: Address to receive protocol fees (required)
 *      - MAX_TOTAL_FEE_RATE: Maximum total fee rate in basis points (default: 5 = 0.05%)
 *      - PROTOCOL_FEE_PERCENTAGE: Protocol fee percentage 0-100 (default: 25 = 25%)
 *      - ARBITER_ADDRESS: Address of the arbiter for dispute resolution (required for operator)
 *      - OWNER_ADDRESS: Owner of the operator/factory contracts (required)
 *      - ESCROW_PERIOD: Duration in seconds for escrow lock (default: 300 = 5 minutes)
 *      - FREEZE_POLICY: Address of freeze policy contract (optional, defaults to address(0) = no freeze support)
 *                       Options:
 *                       - address(0) or empty: No freeze policy (freeze/unfreeze disabled)
 *                       - PayerFreezePolicy address: Only payer can freeze/unfreeze their own payments
 *                       - Custom IFreezePolicy address: Custom authorization logic (must implement IFreezePolicy)
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
    address public releaseCondition;
    address public operator;
    address public refundRequest;
    address public freezePolicy;
    address public operatorFactory;
    address public conditionFactory;

    function run() public {
        // Get configuration from environment variables
        address protocolFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        address arbiter = vm.envOr("ARBITER_ADDRESS", address(0));
        address owner = vm.envAddress("OWNER_ADDRESS");
        uint256 maxTotalFeeRate = vm.envOr("MAX_TOTAL_FEE_RATE", uint256(5));
        uint256 protocolFeePercentage = vm.envOr("PROTOCOL_FEE_PERCENTAGE", uint256(25));
        uint256 escrowPeriod = vm.envOr("ESCROW_PERIOD", uint256(300)); // 5 minutes default
        address freezePolicyAddress = vm.envOr("FREEZE_POLICY", address(0));

        vm.startBroadcast();

        console.log("=== Deploying x402r Contracts ===");
        console.log("Protocol fee recipient:", protocolFeeRecipient);
        console.log("Owner:", owner);
        console.log("Max total fee rate (basis points):", maxTotalFeeRate);
        console.log("Protocol fee percentage:", protocolFeePercentage);
        console.log("Escrow period (seconds):", escrowPeriod);
        if (arbiter != address(0)) {
            console.log("Arbiter:", arbiter);
        }

        // Validate escrow period for current chain
        uint256 chainId = block.chainid;
        bool isL1 = chainId == 1; // Ethereum mainnet
        _validateEscrowPeriod(escrowPeriod, isL1);

        // Step 1: Deploy Base Commerce Payments (with partialVoid)
        console.log("\n=== Step 1: Deploying AuthCaptureEscrow ===");
        AuthCaptureEscrow authCaptureEscrow = new AuthCaptureEscrow();
        escrow = address(authCaptureEscrow);
        console.log("AuthCaptureEscrow:", escrow);

        console.log("\n=== Step 2: Deploying ERC3009PaymentCollector ===");
        ERC3009PaymentCollector collector = new ERC3009PaymentCollector(escrow, MULTICALL3);
        erc3009Collector = address(collector);
        console.log("ERC3009PaymentCollector:", erc3009Collector);

        // Step 2: Set freeze policy (use provided address or address(0) for no freeze support)
        freezePolicy = freezePolicyAddress;
        if (freezePolicy == address(0)) {
            console.log("\n=== Step 3: No freeze policy (freeze not allowed) ===");
            console.log("FreezePolicy: address(0) - freeze/unfreeze disabled");
        } else {
            console.log("\n=== Step 3: Using freeze policy ===");
            console.log("FreezePolicy:", freezePolicy);
        }

        // Step 3: Deploy Release Condition Factory and instance
        console.log("\n=== Step 4: Deploying EscrowPeriodConditionFactory ===");
        EscrowPeriodConditionFactory conditionFactoryContract = new EscrowPeriodConditionFactory();
        conditionFactory = address(conditionFactoryContract);
        console.log("EscrowPeriodConditionFactory:", conditionFactory);

        console.log("\n=== Step 5: Deploying condition via factory ===");
        releaseCondition = conditionFactoryContract.deployCondition(escrowPeriod, freezePolicy);
        console.log("EscrowPeriodCondition:", releaseCondition);

        // Step 4: Deploy ArbitrationOperator Factory and instance
        console.log("\n=== Step 6: Deploying ArbitrationOperatorFactory ===");
        if (arbiter == address(0)) {
            revert("ARBITER_ADDRESS required");
        }
        ArbitrationOperatorFactory operatorFactoryContract = new ArbitrationOperatorFactory(
            escrow,
            protocolFeeRecipient,
            maxTotalFeeRate,
            protocolFeePercentage,
            owner
        );
        operatorFactory = address(operatorFactoryContract);
        console.log("ArbitrationOperatorFactory:", operatorFactory);

        console.log("\n=== Step 7: Deploying operator via factory ===");
        operator = operatorFactoryContract.deployOperator(arbiter, releaseCondition);
        console.log("ArbitrationOperator:", operator);

        // Step 5: Deploy RefundRequest
        console.log("\n=== Step 8: Deploying RefundRequest ===");
        RefundRequest refundRequestContract = new RefundRequest();
        refundRequest = address(refundRequestContract);
        console.log("RefundRequest:", refundRequest);

        vm.stopBroadcast();

        // Print deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("AuthCaptureEscrow:", escrow);
        console.log("ERC3009PaymentCollector:", erc3009Collector);
        console.log("EscrowPeriodCondition:", releaseCondition);
        if (freezePolicy != address(0)) {
            console.log("FreezePolicy:", freezePolicy);
        } else {
            console.log("FreezePolicy: address(0) - freeze not allowed");
        }
        console.log("EscrowPeriodConditionFactory:", conditionFactory);
        console.log("ArbitrationOperator:", operator);
        console.log("ArbitrationOperatorFactory:", operatorFactory);
        console.log("RefundRequest:", refundRequest);

        console.log("\n=== Environment Variables for Next Steps ===");
        console.log("ESCROW_ADDRESS=", escrow);
        console.log("RELEASE_CONDITION=", releaseCondition);
        console.log("OPERATOR_ADDRESS=", operator);
        console.log("REFUND_REQUEST_ADDRESS=", refundRequest);
        console.log("CONDITION_FACTORY_ADDRESS=", conditionFactory);
        console.log("OPERATOR_FACTORY_ADDRESS=", operatorFactory);
    }

    function _validateEscrowPeriod(uint256 escrowPeriod, bool isL1) internal pure {
        uint256 minPeriod = isL1 ? 300 : 30; // 5 minutes for L1, 30 seconds for L2

        if (escrowPeriod < minPeriod) {
            console.log("");
            console.log("!!! WARNING: ESCROW PERIOD BELOW RECOMMENDED MINIMUM !!!");
            console.log("Current period:", escrowPeriod, "seconds");
            console.log("Minimum recommended:", minPeriod, "seconds");
            if (isL1) {
                console.log("Risk: Miners can manipulate timestamps by ~15 seconds");
            }
            console.log("");
        }

        if (escrowPeriod < 60) {
            console.log("!!! CRITICAL: Escrow period < 60s is NOT RECOMMENDED !!!");
            console.log("This may expose users to timestamp manipulation attacks.");
            console.log("");
        }
    }
}
