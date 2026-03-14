// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RefundRequestEvidence} from "../src/evidence/RefundRequestEvidence.sol";

/**
 * @title DeployRefundRequestEvidence
 * @notice Deploys the RefundRequestEvidence contract for x402r
 * @dev RefundRequestEvidence requires a RefundRequest address as constructor parameter.
 *      Set REFUND_REQUEST_ADDRESS env var to the deployed RefundRequest on the target chain.
 *
 *      Usage:
 *      REFUND_REQUEST_ADDRESS=0x... forge script script/DeployRefundRequestEvidence.s.sol:DeployRefundRequestEvidence \
 *        --rpc-url <RPC> \
 *        --broadcast \
 *        --verify \
 *        -vvvv
 */
contract DeployRefundRequestEvidence is Script {
    function run() public {
        address refundRequestAddr = vm.envAddress("REFUND_REQUEST_ADDRESS");
        require(refundRequestAddr != address(0), "REFUND_REQUEST_ADDRESS must be set");

        vm.startBroadcast();

        console.log("=== Deploying RefundRequestEvidence ===");
        console.log("RefundRequest:", refundRequestAddr);

        RefundRequestEvidence evidence = new RefundRequestEvidence(refundRequestAddr);

        console.log("\n=== Deployment Summary ===");
        console.log("RefundRequestEvidence:", address(evidence));

        vm.stopBroadcast();
    }
}
