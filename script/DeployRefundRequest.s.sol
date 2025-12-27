// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {RefundRequest} from "../src/simple/main/requests/RefundRequest.sol";

/**
 * @title DeployRefundRequest
 * @notice Deploys the RefundRequest contract
 * @dev This script deploys the RefundRequest contract which depends on:
 *      - Escrow address (SHARED_ESCROW_ADDRESS env var or must be provided)
 */
contract DeployRefundRequest is Script {
    function run() public {
        uint256 chainId = block.chainid;
        
        // Escrow address - REQUIRED (should be deployed first using DeployEscrow.s.sol)
        address escrowAddress = vm.envOr("SHARED_ESCROW_ADDRESS", address(0));
        require(escrowAddress != address(0), "SHARED_ESCROW_ADDRESS must be set");
        
        vm.startBroadcast();
        
        console.log("=== Deploying RefundRequest ===");
        console.log("Chain ID:", chainId);
        console.log("Escrow address:", escrowAddress);
        
        // Deploy RefundRequest
        RefundRequest refundRequest = new RefundRequest(escrowAddress);
        
        console.log("\n=== Deployment Summary ===");
        console.log("RefundRequest:", address(refundRequest));
        console.log("\n=== Configuration ===");
        console.log("REFUND_REQUEST_ADDRESS=", address(refundRequest));
        console.log("SHARED_ESCROW_ADDRESS=", escrowAddress);
        
        vm.stopBroadcast();
    }
}

