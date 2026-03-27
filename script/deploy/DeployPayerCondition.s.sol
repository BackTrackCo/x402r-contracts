// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {Create3Deployer} from "./Create3Deployer.sol";
import {PayerCondition} from "../../src/plugins/conditions/access/PayerCondition.sol";

contract DeployPayerCondition is Create3Deployer {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        string memory label = vm.envString("LABEL");
        string memory salt = vm.envOr("SALT", string(""));

        vm.startBroadcast(deployerPk);
        address deployed = _deploy3(label, salt, abi.encodePacked(type(PayerCondition).creationCode));
        console.log("PayerCondition:", deployed);
        vm.stopBroadcast();
    }
}
