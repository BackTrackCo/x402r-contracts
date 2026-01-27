// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {RefundRequest} from "../src/requests/refund/RefundRequest.sol";

/**
 * @title DeployRefundRequest
 * @notice Deploys the RefundRequest contract for x402r
 * @dev RefundRequest is a singleton contract with no constructor parameters.
 *      It reads the REFUND_IN_ESCROW_CONDITION from each operator for authorization.
 *
 *      Usage:
 *      forge script script/DeployRefundRequest.s.sol:DeployRefundRequest \
 *        --rpc-url $BASE_SEPOLIA_RPC \
 *        --broadcast \
 *        --verify \
 *        -vvvv
 */
contract DeployRefundRequest is Script {
    function run() public {
        vm.startBroadcast();

        console.log("=== Deploying RefundRequest ===");

        RefundRequest refundRequest = new RefundRequest();

        console.log("\n=== Deployment Summary ===");
        console.log("RefundRequest:", address(refundRequest));

        vm.stopBroadcast();
    }
}
