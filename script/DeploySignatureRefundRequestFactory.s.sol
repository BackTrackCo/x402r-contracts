// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RefundRequest} from "../src/requests/refund/RefundRequest.sol";

/**
 * @title DeployRefundRequest
 * @notice Deploy RefundRequest singleton (no constructor args)
 *
 *      Usage:
 *      forge script script/DeploySignatureRefundRequestFactory.s.sol:DeployRefundRequest \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        --private-key $PRIVATE_KEY
 */
contract DeployRefundRequest is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying RefundRequest ===");

        RefundRequest refundRequest = new RefundRequest();
        console.log("RefundRequest:", address(refundRequest));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("RefundRequest:", address(refundRequest));
    }
}
