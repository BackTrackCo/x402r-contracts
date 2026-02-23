// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SignatureRefundRequestFactory} from "../src/requests/refund/SignatureRefundRequestFactory.sol";

/**
 * @title DeploySignatureRefundRequestFactory
 * @notice Deploy SignatureRefundRequestFactory for deterministic SignatureRefundRequest deployment
 *
 *      Usage:
 *      forge script script/DeploySignatureRefundRequestFactory.s.sol:DeploySignatureRefundRequestFactory \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        --private-key $PRIVATE_KEY
 */
contract DeploySignatureRefundRequestFactory is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying SignatureRefundRequestFactory ===");

        SignatureRefundRequestFactory factory = new SignatureRefundRequestFactory();
        console.log("SignatureRefundRequestFactory:", address(factory));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("SignatureRefundRequestFactory:", address(factory));
    }
}
