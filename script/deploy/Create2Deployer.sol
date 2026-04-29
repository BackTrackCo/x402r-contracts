// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

/// @notice Minimal interface for CreateX's CREATE2 deployment
interface ICreateX {
    function deployCreate2(bytes32 salt, bytes memory initCode) external payable returns (address);
}

/// @notice Shared base for CREATE2 deploy scripts using CreateX permissionless salts.
/// @dev Salt format (CreateX permissionless, no chainId mixing):
///        bytes20(0) || bytes1(0x00) || bytes11(keccak256(label))
///
///      Why permissionless (not deployer-guarded):
///      - Matches the convention used by Permit2, UniversalRouter, Seaport, EntryPoint, and
///        upstream commerce-payments: anyone can verify and reproduce the deployment.
///      - Same factory + same label + byte-identical initCode = same address on every chain
///        (assuming CreateX is deployed there), regardless of who broadcasts the tx.
///      - No single-key dependency. The canonical namespace is not bricked if any deployer EOA
///        is lost or rotated; the bytecode + salt are the trust root, not an EOA.
///      - With CREATE2, the address is a pure function of the bytecode — anyone deploying the
///        exact x402r bytecode at the canonical salt is, by definition, deploying x402r.
///
///      Note: in permissionless mode CreateX hashes the salt internally, so an off-chain
///      `computeCreate2Address(salt, hash, factory)` does not match the deployed address. To
///      predict, compute `keccak256(0xff || CreateX || keccak256(salt) || initCodeHash)[12:]`.
abstract contract Create2Deployer is Script {
    ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function _deploy2(string memory label, bytes memory initCode) internal returns (address deployed) {
        bytes32 salt = bytes32(abi.encodePacked(bytes20(0), bytes1(0x00), bytes11(keccak256(bytes(label)))));
        deployed = CREATEX.deployCreate2(salt, initCode);
    }
}
