// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {StaticAddressConditionFactory} from "../src/plugins/conditions/access/StaticAddressConditionFactory.sol";

/**
 * @title DeployStaticAddressConditionFactory
 * @notice Deploy StaticAddressConditionFactory for deterministic StaticAddressCondition deployment
 *
 *      Usage:
 *      forge script script/DeployStaticAddressConditionFactory.s.sol:DeployStaticAddressConditionFactory \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        --private-key $PRIVATE_KEY
 */
contract DeployStaticAddressConditionFactory is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying StaticAddressConditionFactory ===");

        StaticAddressConditionFactory factory = new StaticAddressConditionFactory();
        console.log("StaticAddressConditionFactory:", address(factory));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("StaticAddressConditionFactory:", address(factory));
    }
}
