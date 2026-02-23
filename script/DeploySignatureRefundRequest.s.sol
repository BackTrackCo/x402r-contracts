// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SignatureRefundRequest} from "../src/requests/refund/SignatureRefundRequest.sol";

/**
 * @title DeploySignatureRefundRequest
 * @notice Deploy SignatureRefundRequest with a reference to a specific SignatureCondition
 *
 *      Requires SIGNATURE_CONDITION_ADDRESS env var.
 *
 *      Usage:
 *      SIGNATURE_CONDITION_ADDRESS=0x... forge script \
 *        script/DeploySignatureRefundRequest.s.sol:DeploySignatureRefundRequest \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        --private-key $PRIVATE_KEY
 */
contract DeploySignatureRefundRequest is Script {
    function run() public {
        address signatureCondition = vm.envAddress("SIGNATURE_CONDITION_ADDRESS");

        vm.startBroadcast();

        console.log("=== Deploying SignatureRefundRequest ===");
        console.log("SignatureCondition:", signatureCondition);

        SignatureRefundRequest refundRequest = new SignatureRefundRequest(signatureCondition);
        console.log("SignatureRefundRequest:", address(refundRequest));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("SignatureCondition:", signatureCondition);
        console.log("SignatureRefundRequest:", address(refundRequest));
    }
}
