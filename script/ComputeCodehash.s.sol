// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RecorderCombinator} from "../src/plugins/recorders/combinators/RecorderCombinator.sol";
import {IRecorder} from "../src/plugins/recorders/IRecorder.sol";

contract ComputeCodehash is Script {
    function run() external {
        // Deploy a dummy RecorderCombinator to get its runtime codehash
        IRecorder[] memory recorders = new IRecorder[](1);
        recorders[0] = IRecorder(address(1));
        RecorderCombinator rc = new RecorderCombinator(recorders);
        bytes32 codehash = address(rc).codehash;
        console.log("RecorderCombinator runtime codehash:");
        console.logBytes32(codehash);
    }
}
