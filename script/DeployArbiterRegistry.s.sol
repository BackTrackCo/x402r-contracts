// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ArbiterRegistry} from "../src/registry/ArbiterRegistry.sol";

/**
 * @title DeployArbiterRegistry
 * @notice Deploys the ArbiterRegistry contract for x402r
 * @dev ArbiterRegistry is a singleton contract with no constructor parameters.
 *      Arbiters self-register with a URI pointing to their metadata/API.
 *
 *      Usage:
 *      forge script script/DeployArbiterRegistry.s.sol:DeployArbiterRegistry \
 *        --rpc-url $BASE_SEPOLIA_RPC \
 *        --broadcast \
 *        --verify \
 *        -vvvv
 */
contract DeployArbiterRegistry is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying ArbiterRegistry ===");

        ArbiterRegistry registry = new ArbiterRegistry();

        console.log("\n=== Deployment Summary ===");
        console.log("ArbiterRegistry:", address(registry));

        vm.stopBroadcast();
    }
}
