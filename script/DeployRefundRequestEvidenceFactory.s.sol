// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RefundRequestEvidenceFactory} from "../src/evidence/RefundRequestEvidenceFactory.sol";

/**
 * @title DeployRefundRequestEvidenceFactory
 * @notice Deploys the RefundRequestEvidenceFactory contract
 * @dev No constructor parameters — deploy once per chain.
 *
 *      Usage:
 *      forge script script/DeployRefundRequestEvidenceFactory.s.sol:DeployRefundRequestEvidenceFactory \
 *        --rpc-url <RPC> \
 *        --broadcast \
 *        --verify \
 *        -vvvv
 */
contract DeployRefundRequestEvidenceFactory is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying RefundRequestEvidenceFactory ===");

        RefundRequestEvidenceFactory factory = new RefundRequestEvidenceFactory();

        console.log("\n=== Deployment Summary ===");
        console.log("RefundRequestEvidenceFactory:", address(factory));

        vm.stopBroadcast();
    }
}
