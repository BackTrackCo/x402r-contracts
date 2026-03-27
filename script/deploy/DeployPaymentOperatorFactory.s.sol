// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {Create3Deployer} from "./Create3Deployer.sol";
import {PaymentOperatorFactory} from "../../src/operator/PaymentOperatorFactory.sol";

contract DeployPaymentOperatorFactory is Create3Deployer {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        string memory label = vm.envString("LABEL");
        string memory salt = vm.envOr("SALT", string(""));
        address escrow = vm.envAddress("ESCROW_ADDRESS");
        address protocolFeeConfig = vm.envAddress("PROTOCOL_FEE_CONFIG_ADDRESS");

        vm.startBroadcast(deployerPk);
        address deployed = _deploy3(
            label,
            salt,
            abi.encodePacked(type(PaymentOperatorFactory).creationCode, abi.encode(escrow, protocolFeeConfig))
        );
        console.log("PaymentOperatorFactory:", deployed);
        vm.stopBroadcast();
    }
}
