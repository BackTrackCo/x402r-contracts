// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {Create3Deployer} from "./Create3Deployer.sol";
import {UsdcTvlLimit} from "../../src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol";

contract DeployUsdcTvlLimit is Create3Deployer {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        string memory label = vm.envString("LABEL");
        string memory salt = vm.envOr("SALT", string(""));
        address escrow = vm.envAddress("ESCROW_ADDRESS");
        address usdc = vm.envAddress("USDC_ADDRESS");
        uint256 tvlLimit = vm.envUint("TVL_LIMIT");

        vm.startBroadcast(deployerPk);
        address deployed = _deploy3(
            label, salt, abi.encodePacked(type(UsdcTvlLimit).creationCode, abi.encode(escrow, usdc, tvlLimit))
        );
        console.log("UsdcTvlLimit:", deployed);
        vm.stopBroadcast();
    }
}
