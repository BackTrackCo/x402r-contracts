// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ReceiverRefundCollector} from "../src/collectors/ReceiverRefundCollector.sol";

/**
 * @notice Deploy ReceiverRefundCollector pointing to existing AuthCaptureEscrow.
 *
 * Required environment variables:
 *   ESCROW_ADDRESS - AuthCaptureEscrow contract address
 *
 * Usage (Base Sepolia):
 *   ESCROW_ADDRESS=0x29025c0E9D4239d438e169570818dB9FE0A80873 \
 *   forge script script/DeployReceiverRefundCollector.s.sol --rpc-url base-sepolia --broadcast --verify -vvvv
 *
 * Usage (Base Mainnet):
 *   source .env.production
 *   forge script script/DeployReceiverRefundCollector.s.sol --rpc-url base --broadcast --verify -vvvv
 */
contract DeployReceiverRefundCollector is Script {
    function run() public {
        address escrow = vm.envAddress("ESCROW_ADDRESS");

        console2.log("=== Deploying ReceiverRefundCollector ===");
        console2.log("Network:", block.chainid);
        console2.log("Escrow:", escrow);

        vm.startBroadcast();

        ReceiverRefundCollector collector = new ReceiverRefundCollector(escrow);

        vm.stopBroadcast();

        console2.log("\n=== Deployment Summary ===");
        console2.log("ReceiverRefundCollector:", address(collector));
        console2.log("  authCaptureEscrow:", escrow);
    }
}
