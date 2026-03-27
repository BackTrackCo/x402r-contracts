// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {Create3Deployer} from "./Create3Deployer.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

contract DeployEscrow is Create3Deployer {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        string memory label = vm.envString("LABEL");
        string memory salt = vm.envOr("SALT", string(""));

        vm.startBroadcast(deployerPk);
        address deployed = _deploy3(label, salt, abi.encodePacked(type(AuthCaptureEscrow).creationCode));
        console.log("AuthCaptureEscrow:", deployed);
        vm.stopBroadcast();
    }
}
