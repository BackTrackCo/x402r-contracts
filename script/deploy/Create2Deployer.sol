// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

/// @notice Minimal interface for CreateX's CREATE2 deployment
interface ICreateX {
    function deployCreate2(bytes32 salt, bytes memory initCode) external payable returns (address);
}

/// @notice Shared base for CREATE2 deploy scripts using CreateX guarded salts.
/// @dev Salt format (CreateX guarded):
///        bytes20(msg.sender) || bytes1(0x00) || bytes11(keccak256(label))
///      Only the deployer EOA encoded in the top 20 bytes can use the salt, preventing
///      address squatting. Same factory + same deployer + same label + byte-identical
///      initCode = same address on every chain (assuming CreateX is deployed there).
///
///      Note: in guarded mode CreateX hashes msg.sender into the effective salt, so an
///      off-chain `computeCreate2Address(salt, hash, factory)` does not match the deployed
///      address. To predict a guarded address, compute
///      `keccak256(0xff || CreateX || keccak256(msg.sender || salt) || initCodeHash)[12:]`
///      directly. We omit a helper here because it would invite the wrong-formula footgun.
abstract contract Create2Deployer is Script {
    ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function _deploy2(string memory label, bytes memory initCode) internal returns (address deployed) {
        bytes32 salt = bytes32(abi.encodePacked(msg.sender, bytes1(0x00), bytes11(keccak256(bytes(label)))));
        deployed = CREATEX.deployCreate2(salt, initCode);
    }
}
