// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RefundRequestConditionFactory} from "../src/requests/refund/RefundRequestConditionFactory.sol";

/**
 * @title DeployRefundRequestConditionFactory
 * @notice Deploy RefundRequestConditionFactory for deterministic per-arbiter deployment
 *
 *      Usage:
 *      forge script script/DeploySignatureRefundRequestFactory.s.sol:DeployRefundRequestConditionFactory \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        --private-key $PRIVATE_KEY
 */
contract DeployRefundRequestConditionFactory is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying RefundRequestConditionFactory ===");

        RefundRequestConditionFactory factory = new RefundRequestConditionFactory();
        console.log("RefundRequestConditionFactory:", address(factory));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("RefundRequestConditionFactory:", address(factory));
    }
}
