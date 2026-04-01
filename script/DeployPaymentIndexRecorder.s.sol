// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PaymentIndexRecorder} from "../src/plugins/recorders/PaymentIndexRecorder.sol";
import {RecorderCombinator} from "../src/plugins/recorders/combinators/RecorderCombinator.sol";
import {IRecorder} from "../src/plugins/recorders/IRecorder.sol";

/// @notice Minimal interface for CreateX's CREATE3 deployment
interface ICreateX {
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address);
    function computeCreate3Address(bytes32 salt, address deployer) external view returns (address);
}

/**
 * @title DeployPaymentIndexRecorder
 * @notice Deploy PaymentIndexRecorder singleton via CREATE3.
 *         Same address on all chains. Shared across all operators.
 *
 * @dev The authorizedCodehash is the runtime codehash of RecorderCombinator,
 *      which is the same for all instances (constructor args go to storage).
 *      This lets RecorderCombinator call PaymentIndexRecorder.record() on
 *      behalf of the operator.
 *
 * Usage:
 *   forge script script/DeployPaymentIndexRecorder.s.sol \
 *     --rpc-url <RPC> --broadcast --verify -vvvv
 */
contract DeployPaymentIndexRecorder is Script {
    ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    // Unified CREATE3 AuthCaptureEscrow address (same on all chains)
    address constant ESCROW = 0xBC151792f80C0EB1973d56b0235e6bee2A60e245;

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        // Step 1: Compute RecorderCombinator runtime codehash
        // Deploy a temporary instance to read EXTCODEHASH (constructor args
        // don't affect runtime bytecode, so any args work)
        IRecorder[] memory dummyRecorders = new IRecorder[](1);
        dummyRecorders[0] = IRecorder(address(1));
        RecorderCombinator tempCombinator = new RecorderCombinator(dummyRecorders);
        bytes32 recorderCombinatorCodehash = address(tempCombinator).codehash;

        console.log("\n========================================");
        console.log("  PaymentIndexRecorder CREATE3 Deploy");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Escrow:", ESCROW);
        console.logBytes32(recorderCombinatorCodehash);

        // Step 2: Compute CREATE3 address (for preview)
        bytes32 salt =
            bytes32(abi.encodePacked(deployer, bytes1(0x00), bytes11(keccak256(bytes("payment-index-recorder-v2")))));
        address predicted = CREATEX.computeCreate3Address(salt, deployer);
        console.log("Predicted address:", predicted);

        // Step 3: Deploy
        vm.startBroadcast(deployerPk);

        bytes memory initCode =
            abi.encodePacked(type(PaymentIndexRecorder).creationCode, abi.encode(ESCROW, recorderCombinatorCodehash));
        address deployed = CREATEX.deployCreate3(salt, initCode);

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("  DEPLOYED");
        console.log("========================================");
        console.log("PaymentIndexRecorder:", deployed);
        console.log("RecorderCombinator codehash:");
        console.logBytes32(recorderCombinatorCodehash);
        console.log("\nUpdate SDK config:");
        console.log("  recorders.paymentIndexRecorder =", deployed);
        console.log("  recorderCombinatorCodehash =");
        console.logBytes32(recorderCombinatorCodehash);
    }
}
