// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/plugins/fees/StaticFeeCalculator.sol";
import {StaticAddressCondition} from "../src/plugins/conditions/access/StaticAddressCondition.sol";

/**
 * @title DeployPaymentOperatorFactory
 * @notice Deploys ProtocolFeeConfig and PaymentOperatorFactory contracts
 * @dev This script deploys:
 *      1. StaticFeeCalculator (optional) - Protocol fee calculator
 *      2. ProtocolFeeConfig - Shared protocol fee configuration
 *      3. PaymentOperatorFactory - Generic payment operator factory
 *      4. StaticAddressCondition (optional example) - Designated address condition
 *
 *      Environment variables:
 *      - ESCROW_ADDRESS: Base Commerce Payments escrow contract address (required)
 *      - PROTOCOL_FEE_RECIPIENT: Address to receive protocol fees (required)
 *      - PROTOCOL_FEE_BPS: Protocol fee in basis points (default: 0 = no protocol fee)
 *      - OWNER_ADDRESS: Owner of the factory and config contracts (required)
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
        uint256 protocolFeeBps = vm.envOr("PROTOCOL_FEE_BPS", uint256(0));

        // Optional: Example designated address for StaticAddressCondition
        address exampleDesignatedAddress = vm.envOr("EXAMPLE_DESIGNATED_ADDRESS", address(0));

        vm.startBroadcast();

        console.log("=== Deploying Modular Fee System ===");
        console.log("Escrow address:", escrow);
        console.log("Protocol fee recipient:", protocolFeeRecipient);
        console.log("Protocol fee (bps):", protocolFeeBps);
        console.log("Owner:", owner);

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

        // Deploy PaymentOperatorFactory
        PaymentOperatorFactory factory = new PaymentOperatorFactory(escrow, address(protocolFeeConfig));

        console.log("\n=== Deployment Summary ===");
        console.log("PaymentOperatorFactory:", address(factory));
        console.log("Escrow:", factory.ESCROW());
        console.log("ProtocolFeeConfig:", factory.PROTOCOL_FEE_CONFIG());

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
        console.log("PROTOCOL_FEE_CONFIG_ADDRESS=", address(protocolFeeConfig));

        vm.stopBroadcast();
    }
}
