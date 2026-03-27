// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {Create3Deployer} from "./Create3Deployer.sol";
import {ReceiverCondition} from "../../src/plugins/conditions/access/ReceiverCondition.sol";

contract DeployReceiverCondition is Create3Deployer {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        string memory label = vm.envString("LABEL");
        string memory salt = vm.envOr("SALT", string(""));

        vm.startBroadcast(deployerPk);
        address deployed = _deploy3(label, salt, abi.encodePacked(type(ReceiverCondition).creationCode));
        console.log("ReceiverCondition:", deployed);
        vm.stopBroadcast();
    }
}
