// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SignatureConditionFactory} from "../src/plugins/conditions/access/signature/SignatureConditionFactory.sol";

/**
 * @title DeploySignatureConditionFactory
 * @notice Deploy SignatureConditionFactory for deterministic SignatureCondition deployment
 *
 *      Usage:
 *      forge script script/DeploySignatureConditionFactory.s.sol:DeploySignatureConditionFactory \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        --private-key $PRIVATE_KEY
 */
contract DeploySignatureConditionFactory is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying SignatureConditionFactory ===");

        SignatureConditionFactory factory = new SignatureConditionFactory();
        console.log("SignatureConditionFactory:", address(factory));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("SignatureConditionFactory:", address(factory));
    }
}
