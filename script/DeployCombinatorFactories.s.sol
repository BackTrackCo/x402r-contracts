// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AndConditionFactory} from "../src/plugins/conditions/combinators/AndConditionFactory.sol";
import {OrConditionFactory} from "../src/plugins/conditions/combinators/OrConditionFactory.sol";
import {NotConditionFactory} from "../src/plugins/conditions/combinators/NotConditionFactory.sol";
import {RecorderCombinatorFactory} from "../src/plugins/recorders/combinators/RecorderCombinatorFactory.sol";

/**
 * @title DeployCombinatorFactories
 * @notice Deploy combinator factories for conditions (And, Or, Not) and recorders
 *
 *      Usage:
 *      forge script script/DeployCombinatorFactories.s.sol:DeployCombinatorFactories \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        --private-key $PRIVATE_KEY
 */
contract DeployCombinatorFactories is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying Combinator Factories ===");

        console.log("\n--- Condition Combinators ---");
        AndConditionFactory andFactory = new AndConditionFactory();
        console.log("AndConditionFactory:", address(andFactory));

        OrConditionFactory orFactory = new OrConditionFactory();
        console.log("OrConditionFactory:", address(orFactory));

        NotConditionFactory notFactory = new NotConditionFactory();
        console.log("NotConditionFactory:", address(notFactory));

        console.log("\n--- Recorder Combinator ---");
        RecorderCombinatorFactory recorderFactory = new RecorderCombinatorFactory();
        console.log("RecorderCombinatorFactory:", address(recorderFactory));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("AndConditionFactory:", address(andFactory));
        console.log("OrConditionFactory:", address(orFactory));
        console.log("NotConditionFactory:", address(notFactory));
        console.log("RecorderCombinatorFactory:", address(recorderFactory));
    }
}
