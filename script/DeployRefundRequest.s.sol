// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {RefundRequest} from "../src/commerce-payments/requests/RefundRequest.sol";

/**
 * @title DeployRefundRequest
 * @notice Deploys the RefundRequest contract
 * @dev This script deploys the RefundRequest contract for managing refund requests
 *      for Base Commerce Payments authorizations.
 * 
 *      Environment variables:
 *      - OPERATOR_ADDRESS: Address of the ArbiterationOperator contract (required)
 */
contract DeployRefundRequest is Script {
    function run() public {
        // Get operator address from environment variables
        address operator = vm.envAddress("OPERATOR_ADDRESS");
        
        vm.startBroadcast();
        
        console.log("=== Deploying RefundRequest ===");
        console.log("Operator address:", operator);
        
        // Deploy RefundRequest
        RefundRequest refundRequest = new RefundRequest(operator);
        
        console.log("\n=== Deployment Summary ===");
        console.log("RefundRequest:", address(refundRequest));
        console.log("Operator:", address(refundRequest.OPERATOR()));
        console.log("\n=== Configuration ===");
        console.log("REFUND_REQUEST_ADDRESS=", address(refundRequest));
        
        vm.stopBroadcast();
    }
}

