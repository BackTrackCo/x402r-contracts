// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {Create3Deployer} from "./Create3Deployer.sol";
import {ProtocolFeeConfig} from "../../src/plugins/fees/ProtocolFeeConfig.sol";

contract DeployProtocolFeeConfig is Create3Deployer {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        string memory label = vm.envString("LABEL");
        string memory salt = vm.envOr("SALT", string(""));
        address calculator = vm.envOr("CALCULATOR_ADDRESS", address(0));
        address feeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        address owner = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPk);
        address deployed = _deploy3(
            label,
            salt,
            abi.encodePacked(type(ProtocolFeeConfig).creationCode, abi.encode(calculator, feeRecipient, owner))
        );
        console.log("ProtocolFeeConfig:", deployed);
        vm.stopBroadcast();
    }
}
