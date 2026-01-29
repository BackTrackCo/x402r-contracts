// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {FreezePolicyFactory} from "../src/plugins/freeze/freeze-policy/FreezePolicyFactory.sol";
import {PayerCondition} from "../src/plugins/conditions/access/PayerCondition.sol";
import {ReceiverCondition} from "../src/plugins/conditions/access/ReceiverCondition.sol";
import {AlwaysTrueCondition} from "../src/plugins/conditions/access/AlwaysTrueCondition.sol";

/**
 * @title DeployFreezePolicyFactory
 * @notice Deploy FreezePolicyFactory and condition singletons
 *
 *      Usage:
 *      forge script script/DeployFreezePolicyFactory.s.sol:DeployFreezePolicyFactory \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        --private-key $PRIVATE_KEY
 */
contract DeployFreezePolicyFactory is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying Condition Singletons ===");

        PayerCondition payerCondition = new PayerCondition();
        console.log("PayerCondition:", address(payerCondition));

        ReceiverCondition receiverCondition = new ReceiverCondition();
        console.log("ReceiverCondition:", address(receiverCondition));

        AlwaysTrueCondition alwaysTrueCondition = new AlwaysTrueCondition();
        console.log("AlwaysTrueCondition:", address(alwaysTrueCondition));

        console.log("\n=== Deploying FreezePolicyFactory ===");

        FreezePolicyFactory factory = new FreezePolicyFactory();
        console.log("FreezePolicyFactory:", address(factory));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("PayerCondition:", address(payerCondition));
        console.log("ReceiverCondition:", address(receiverCondition));
        console.log("AlwaysTrueCondition:", address(alwaysTrueCondition));
        console.log("FreezePolicyFactory:", address(factory));
    }
}
