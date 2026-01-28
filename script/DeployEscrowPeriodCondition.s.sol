// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {EscrowPeriodFactory} from "../src/plugins/escrow-period/EscrowPeriodFactory.sol";

/**
 * @title DeployEscrowPeriodCondition
 * @notice Deploys the EscrowPeriodFactory
 * @dev This script deploys only the EscrowPeriodFactory.
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

        console.log("=== Deploying EscrowPeriodFactory ===");
        console.log("Escrow address:", escrowAddress);

        // Deploy factory with escrow reference
        EscrowPeriodFactory factory = new EscrowPeriodFactory(escrowAddress);
        console.log("Factory deployed at:", address(factory));

        console.log("\n=== Deployment Summary ===");
        console.log("EscrowPeriodFactory:", address(factory));

        console.log("\n=== Next Steps ===");
        console.log("Use the factory to deploy EscrowPeriod instances on-demand:");
        console.log("ESCROW_PERIOD_FACTORY_ADDRESS=", address(factory));
        console.log("\nExample: factory.deploy(escrowPeriod, freezePolicy, authorizedCodehash)");

        vm.stopBroadcast();
    }
}
