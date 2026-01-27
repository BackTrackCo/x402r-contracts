// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {EscrowPeriodConditionFactory} from "../src/conditions/escrow-period/EscrowPeriodConditionFactory.sol";

/**
 * @title DeployEscrowPeriodCondition
 * @notice Deploys the EscrowPeriodConditionFactory
 * @dev This script deploys only the EscrowPeriodConditionFactory.
 *      Factory instances should be deployed on-demand via the SDK or by calling
 *      the factory's deploy() method directly.
 *
 *      Required environment variables:
 *        ESCROW_ADDRESS - Address of the AuthCaptureEscrow contract
 */
contract DeployEscrowPeriodCondition is Script {
    function run() public {
        address escrowAddress = vm.envAddress("ESCROW_ADDRESS");

        vm.startBroadcast();

        console.log("=== Deploying EscrowPeriodConditionFactory ===");
        console.log("Escrow address:", escrowAddress);

        // Deploy factory with escrow reference
        EscrowPeriodConditionFactory factory = new EscrowPeriodConditionFactory(escrowAddress);
        console.log("Factory deployed at:", address(factory));

        console.log("\n=== Deployment Summary ===");
        console.log("EscrowPeriodConditionFactory:", address(factory));

        console.log("\n=== Next Steps ===");
        console.log("Use the factory to deploy condition instances on-demand:");
        console.log("CONDITION_FACTORY_ADDRESS=", address(factory));
        console.log("\nExample: factory.deployCondition(escrowPeriod, freezePolicy)");

        vm.stopBroadcast();
    }
}
