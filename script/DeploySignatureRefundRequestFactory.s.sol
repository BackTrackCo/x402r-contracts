// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RefundRequestFactory} from "../src/requests/refund/RefundRequestFactory.sol";

/**
 * @title DeployRefundRequestFactory
 * @notice Deploy RefundRequestFactory for deterministic RefundRequest deployment
 *
 *      Usage:
 *      forge script script/DeploySignatureRefundRequestFactory.s.sol:DeployRefundRequestFactory \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        --private-key $PRIVATE_KEY
 */
contract DeployRefundRequestFactory is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying RefundRequestFactory ===");

        RefundRequestFactory factory = new RefundRequestFactory();
        console.log("RefundRequestFactory:", address(factory));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("RefundRequestFactory:", address(factory));
    }
}
