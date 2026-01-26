// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {PaymentOperatorFactory} from "../src/commerce-payments/operator/PaymentOperatorFactory.sol";
import {StaticAddressCondition} from "../src/conditions/StaticAddressCondition.sol";

/**
 * @title DeployPaymentOperatorFactory
 * @notice Deploys the PaymentOperatorFactory contract and example StaticAddressCondition
 * @dev This script deploys:
 *      1. PaymentOperatorFactory - Generic payment operator factory
 *      2. StaticAddressCondition (optional example) - Designated address condition
 *
 *      Environment variables:
 *      - ESCROW_ADDRESS: Base Commerce Payments escrow contract address (required)
 *      - PROTOCOL_FEE_RECIPIENT: Address to receive protocol fees (required)
 *      - MAX_TOTAL_FEE_RATE: Maximum total fee rate in basis points (default: 5 = 0.05%)
 *      - PROTOCOL_FEE_PERCENTAGE: Protocol fee percentage 0-100 (default: 25 = 25%)
 *      - OWNER_ADDRESS: Owner of the factory contract (required)
 *      - EXAMPLE_DESIGNATED_ADDRESS: Deploy example StaticAddressCondition with this address (optional)
 *
 *      Usage:
 *      forge script script/DeployPaymentOperatorFactory.s.sol:DeployPaymentOperatorFactory \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        -vvvv
 */
contract DeployPaymentOperatorFactory is Script {
    function run() public {
        // Get addresses from environment variables
        address escrow = vm.envAddress("ESCROW_ADDRESS");
        address protocolFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        address owner = vm.envAddress("OWNER_ADDRESS");

        // Get fee configuration from environment variables or use defaults
        uint256 maxTotalFeeRate = vm.envOr("MAX_TOTAL_FEE_RATE", uint256(5));
        uint256 protocolFeePercentage = vm.envOr("PROTOCOL_FEE_PERCENTAGE", uint256(25));

        // Optional: Example designated address for StaticAddressCondition
        address exampleDesignatedAddress = vm.envOr("EXAMPLE_DESIGNATED_ADDRESS", address(0));

        vm.startBroadcast();

        console.log("=== Deploying PaymentOperatorFactory ===");
        console.log("Escrow address:", escrow);
        console.log("Protocol fee recipient:", protocolFeeRecipient);
        console.log("Max total fee rate (basis points):", maxTotalFeeRate);
        console.log("Protocol fee percentage:", protocolFeePercentage);
        console.log("Owner:", owner);

        // Deploy PaymentOperatorFactory
        PaymentOperatorFactory factory = new PaymentOperatorFactory(
            escrow,
            protocolFeeRecipient,
            maxTotalFeeRate,
            protocolFeePercentage,
            owner
        );

        console.log("\n=== Deployment Summary ===");
        console.log("PaymentOperatorFactory:", address(factory));
        console.log("Owner:", factory.owner());
        console.log("Escrow:", factory.ESCROW());
        console.log("Protocol fee recipient:", factory.PROTOCOL_FEE_RECIPIENT());
        console.log("Max total fee rate:", factory.MAX_TOTAL_FEE_RATE());
        console.log("Protocol fee percentage:", factory.PROTOCOL_FEE_PERCENTAGE());

        // Deploy example StaticAddressCondition if requested
        if (exampleDesignatedAddress != address(0)) {
            console.log("\n=== Deploying Example StaticAddressCondition ===");
            console.log("Designated address:", exampleDesignatedAddress);

            StaticAddressCondition exampleCondition = new StaticAddressCondition(exampleDesignatedAddress);

            console.log("StaticAddressCondition (example):", address(exampleCondition));
            console.log("Designated address:", exampleCondition.DESIGNATED_ADDRESS());
        }

        console.log("\n=== Configuration ===");
        console.log("PAYMENT_OPERATOR_FACTORY_ADDRESS=", address(factory));
        console.log("\nNote: Deploy StaticAddressCondition instances as needed for your use case:");
        console.log("  - Marketplace: StaticAddressCondition(arbiterAddress)");
        console.log("  - Subscriptions: StaticAddressCondition(serviceProviderAddress)");
        console.log("  - DAO: StaticAddressCondition(daoMultisigAddress)");
        console.log("  - Platform: StaticAddressCondition(platformTreasuryAddress)");

        vm.stopBroadcast();
    }
}
