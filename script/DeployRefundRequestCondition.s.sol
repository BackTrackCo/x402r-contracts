// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RefundRequestCondition} from "../src/requests/refund/RefundRequestCondition.sol";

/**
 * @title DeployRefundRequestCondition
 * @notice Deploy RefundRequestCondition for a given arbiter
 *
 *      Usage:
 *      ARBITER=0x... forge script script/DeployRefundRequestCondition.s.sol:DeployRefundRequestCondition \
 *        --rpc-url $RPC_URL \
 *        --broadcast \
 *        --verify \
 *        --private-key $PRIVATE_KEY
 */
contract DeployRefundRequestCondition is Script {
    function run() public {
        address arbiter = vm.envAddress("ARBITER");

        vm.startBroadcast();

        console.log("=== Deploying RefundRequestCondition ===");
        console.log("Arbiter:", arbiter);

        RefundRequestCondition refundRequest = new RefundRequestCondition(arbiter);
        console.log("RefundRequestCondition:", address(refundRequest));

        vm.stopBroadcast();
    }
}
