// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {ArbitrationOperator} from "../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {PayerOnly} from "../src/commerce-payments/release-conditions/defaults/PayerOnly.sol";
import {ReceiverOrArbiter} from "../src/commerce-payments/release-conditions/defaults/ReceiverOrArbiter.sol";

/**
 * @title DeployArbitrationOperator
 * @notice Deploys the ArbitrationOperator contract for x402r/Chamba
 * @dev This script deploys the ArbitrationOperator contract with the pull model architecture.
 *      Uses 8 condition slots for flexible policy configuration.
 *
 *      NOTE: For production deployments, prefer using ArbitrationOperatorFactory which handles
 *      deterministic addresses and reusable default conditions. This script is for manual deployments.
 *
 *      Environment variables:
 *      - ESCROW_ADDRESS: Base Commerce Payments escrow contract address (required)
 *      - PROTOCOL_FEE_RECIPIENT: Address to receive protocol fees (required)
 *      - MAX_TOTAL_FEE_RATE: Maximum total fee rate in basis points (default: 5 = 0.05%)
 *      - PROTOCOL_FEE_PERCENTAGE: Protocol fee percentage 0-100 (default: 25 = 25%)
 *      - ARBITER_ADDRESS: Address of the arbiter for dispute resolution (required)
 *      - OWNER_ADDRESS: Owner of the operator contract (required)
 *      - CAN_RELEASE: CAN_RELEASE condition contract address (optional, uses PayerOnly if not set)
 *      - CAN_REFUND_IN_ESCROW: CAN_REFUND_IN_ESCROW condition contract (optional, uses ReceiverOrArbiter if not set)
 */
contract DeployArbitrationOperator is Script {
    function run() public {
        // Get addresses from environment variables
        address escrow = vm.envAddress("ESCROW_ADDRESS");
        address protocolFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        address arbiter = vm.envAddress("ARBITER_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");
        
        // Optional condition overrides
        address canRelease = vm.envOr("CAN_RELEASE", address(0));
        address canRefundInEscrow = vm.envOr("CAN_REFUND_IN_ESCROW", address(0));

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

        // Deploy default conditions if not provided
        PayerOnly payerOnly;
        ReceiverOrArbiter receiverOrArbiter;
        
        if (canRelease == address(0)) {
            payerOnly = new PayerOnly();
            canRelease = address(payerOnly);
            console.log("Deployed PayerOnly:", canRelease);
        }
        
        if (canRefundInEscrow == address(0)) {
            receiverOrArbiter = new ReceiverOrArbiter();
            canRefundInEscrow = address(receiverOrArbiter);
            console.log("Deployed ReceiverOrArbiter:", canRefundInEscrow);
        }

        // Deploy ArbitrationOperator with 8 condition slots
        ArbitrationOperator operator = new ArbitrationOperator(
            escrow,
            protocolFeeRecipient,
            maxTotalFeeRate,
            protocolFeePercentage,
            arbiter,
            owner,
            address(0),         // CAN_AUTHORIZE: anyone can authorize
            address(0),         // NOTE_AUTHORIZE: no tracking
            canRelease,         // CAN_RELEASE: payer only (or custom)
            address(0),         // NOTE_RELEASE: no tracking
            canRefundInEscrow,  // CAN_REFUND_IN_ESCROW: receiver or arbiter
            address(0),         // NOTE_REFUND_IN_ESCROW: no tracking
            address(0),         // CAN_REFUND_POST_ESCROW: anyone
            address(0)          // NOTE_REFUND_POST_ESCROW: no tracking
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
        console.log("CAN_RELEASE:", address(operator.CAN_RELEASE()));
        console.log("CAN_REFUND_IN_ESCROW:", address(operator.CAN_REFUND_IN_ESCROW()));
        console.log("Fees enabled:", operator.feesEnabled());
        console.log("\n=== Configuration ===");
        console.log("OPERATOR_ADDRESS=", address(operator));
        console.log("\nNote: Protocol fees are disabled by default. Use setFeesEnabled(true) to enable.");

        vm.stopBroadcast();
    }
}
