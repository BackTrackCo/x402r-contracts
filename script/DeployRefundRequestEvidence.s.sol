// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RefundRequestEvidence} from "../src/evidence/RefundRequestEvidence.sol";

/**
 * @title DeployRefundRequestEvidence
 * @notice Deploys the RefundRequestEvidence contract for x402r
 * @dev RefundRequestEvidence is a stateless singleton — no constructor parameters.
 *      The RefundRequestCondition address is passed per-call to submitEvidence.
 *
 *      Usage:
 *      forge script script/DeployRefundRequestEvidence.s.sol:DeployRefundRequestEvidence \
 *        --rpc-url <RPC> \
 *        --broadcast \
 *        --verify \
 *        -vvvv
 */
contract DeployRefundRequestEvidence is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying RefundRequestEvidence ===");

        RefundRequestEvidence evidence = new RefundRequestEvidence();

        console.log("\n=== Deployment Summary ===");
        console.log("RefundRequestEvidence:", address(evidence));

        vm.stopBroadcast();
    }
}
