// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {FreezeFactory} from "../src/plugins/freeze/FreezeFactory.sol";

/**
 * @title DeployFreezeFactory
 * @notice Deploys the FreezeFactory
 * @dev This script deploys only the FreezeFactory.
 *      Freeze instances should be deployed on-demand via the SDK or by calling
 *      the factory's deploy() method directly.
 *
 *      Required environment variables:
 *        ESCROW_ADDRESS - Address of the AuthCaptureEscrow contract
 *
 *      Example configurations via deploy():
 *        - Payer freeze/unfreeze (3 days): deploy(PayerCondition, PayerCondition, 3 days, escrowPeriod)
 *        - Payer freeze, Arbiter unfreeze: deploy(PayerCondition, StaticAddressCondition, 0, escrowPeriod)
 *        - Anyone freeze, Receiver unfreeze: deploy(AlwaysTrueCondition, ReceiverCondition, 7 days, escrowPeriod)
 */
contract DeployFreezeFactory is Script {
    function run() public {
        address escrowAddress = vm.envAddress("ESCROW_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying FreezeFactory ===");
        console.log("Escrow address:", escrowAddress);

        // Deploy factory with escrow reference
        FreezeFactory factory = new FreezeFactory(escrowAddress);
        console.log("Factory deployed at:", address(factory));

        console.log("\n=== Deployment Summary ===");
        console.log("FreezeFactory:", address(factory));

        console.log("\n=== Next Steps ===");
        console.log("Use the factory to deploy Freeze instances on-demand:");
        console.log("FREEZE_FACTORY_ADDRESS=", address(factory));
        console.log("\nExample: factory.deploy(freezeCondition, unfreezeCondition, freezeDuration, escrowPeriodContract)");

        vm.stopBroadcast();
    }
}
