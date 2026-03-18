// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";
import {RefundRequestEvidenceFactory} from "../src/evidence/RefundRequestEvidenceFactory.sol";

/**
 * @title DeployRefundRequestEvidenceFactory
 * @notice Deploys the RefundRequestEvidenceFactory via CREATE3 for cross-chain deterministic addresses.
 * @dev The deployed address depends only on the deployer and salt, not the contract bytecode.
 *      Same deployer + same salt = same address on every chain.
 *
 *      Usage:
 *      forge script script/DeployRefundRequestEvidenceFactory.s.sol:DeployRefundRequestEvidenceFactory \
 *        --rpc-url <RPC> \
 *        --broadcast \
 *        --verify \
 *        -vvvv
 */
contract DeployRefundRequestEvidenceFactory is Script {
    bytes32 constant SALT = keccak256("x402r.RefundRequestEvidenceFactory.v1");

    function run() public {
        // Log predicted address before broadcast
        address predicted = CREATE3.predictDeterministicAddress(SALT, address(this));
        console.log("=== Deploying RefundRequestEvidenceFactory (CREATE3) ===");
        console.log("Predicted address:", predicted);

        vm.startBroadcast();

        address deployed = CREATE3.deployDeterministic(type(RefundRequestEvidenceFactory).creationCode, SALT);

        console.log("\n=== Deployment Summary ===");
        console.log("RefundRequestEvidenceFactory:", deployed);

        vm.stopBroadcast();
    }
}
