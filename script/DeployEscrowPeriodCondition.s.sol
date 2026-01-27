// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {EscrowPeriodConditionFactory} from "../src/conditions/escrow-period/EscrowPeriodConditionFactory.sol";

/**
 * @title DeployEscrowPeriodCondition
 * @notice Deploys the EscrowPeriodConditionFactory
 * @dev This script deploys only the EscrowPeriodConditionFactory.
 *      Factory instances should be deployed on-demand via the SDK or by calling
 *      the factory's deployCondition() method directly.
 *
 *      No environment variables required - factory deployment only.
 */
contract DeployEscrowPeriodCondition is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying EscrowPeriodConditionFactory ===");

        // Deploy factory only
        EscrowPeriodConditionFactory factory = new EscrowPeriodConditionFactory();
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
