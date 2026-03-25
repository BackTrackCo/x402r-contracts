// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RefundRequest} from "../src/requests/refund/RefundRequest.sol";

/**
 * @title DeployRefundRequest
 * @notice Deploy RefundRequest with a reference to a specific arbiter address
 *
 *      Requires ARBITER_ADDRESS env var.
 *
 *      Usage:
 *      ARBITER_ADDRESS=0x... forge script \
 *        script/DeploySignatureRefundRequest.s.sol:DeployRefundRequest \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        --private-key $PRIVATE_KEY
 */
contract DeployRefundRequest is Script {
    function run() public {
        address arbiter = vm.envAddress("ARBITER_ADDRESS");

        vm.startBroadcast();

        console.log("=== Deploying RefundRequest ===");
        console.log("Arbiter:", arbiter);

        RefundRequest refundRequest = new RefundRequest(arbiter, false);
        console.log("RefundRequest:", address(refundRequest));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Arbiter:", arbiter);
        console.log("RefundRequest:", address(refundRequest));
    }
}
