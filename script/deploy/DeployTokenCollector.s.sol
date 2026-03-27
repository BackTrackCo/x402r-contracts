// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {Create3Deployer} from "./Create3Deployer.sol";
import {ERC3009PaymentCollector} from "commerce-payments/collectors/ERC3009PaymentCollector.sol";

contract DeployTokenCollector is Create3Deployer {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        string memory label = vm.envString("LABEL");
        string memory salt = vm.envOr("SALT", string(""));
        address escrow = vm.envAddress("ESCROW_ADDRESS");
        address multicall3 = vm.envOr("MULTICALL3_ADDRESS", address(0xcA11bde05977b3631167028862bE2a173976CA11));

        vm.startBroadcast(deployerPk);
        address deployed = _deploy3(
            label, salt, abi.encodePacked(type(ERC3009PaymentCollector).creationCode, abi.encode(escrow, multicall3))
        );
        console.log("ERC3009PaymentCollector:", deployed);
        vm.stopBroadcast();
    }
}
