// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

/// @notice Minimal interface for CreateX's CREATE3 deployment
interface ICreateX {
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address);
    function computeCreate3Address(bytes32 salt, address deployer) external view returns (address);
}

/// @notice Shared base for all CREATE3 deploy scripts.
/// @dev Reads SALT env var and appends it to labels. Use SALT="" for first deployment.
abstract contract Create3Deployer is Script {
    ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function _deploy3(string memory label, string memory salt, bytes memory initCode)
        internal
        returns (address deployed)
    {
        if (bytes(salt).length == 0) {
            console.log("Warning: SALT is empty, deploying at default address for label:", label);
        }
        string memory fullLabel = string.concat(label, salt);
        bytes32 s = bytes32(abi.encodePacked(msg.sender, bytes1(0x00), bytes11(keccak256(bytes(fullLabel)))));
        deployed = CREATEX.deployCreate3(s, initCode);
    }
}
