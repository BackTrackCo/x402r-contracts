// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {StaticFeeCalculatorFactory} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol";

/**
 * @title DeployStaticFeeCalculatorFactory
 * @notice Deploy StaticFeeCalculatorFactory for deterministic StaticFeeCalculator deployment
 *
 *      Usage:
 *      forge script script/DeployStaticFeeCalculatorFactory.s.sol:DeployStaticFeeCalculatorFactory \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        --private-key $PRIVATE_KEY
 */
contract DeployStaticFeeCalculatorFactory is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying StaticFeeCalculatorFactory ===");

        StaticFeeCalculatorFactory factory = new StaticFeeCalculatorFactory();
        console.log("StaticFeeCalculatorFactory:", address(factory));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("StaticFeeCalculatorFactory:", address(factory));
    }
}
