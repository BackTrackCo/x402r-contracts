// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {Create2Deployer} from "./deploy/Create2Deployer.sol";

import {HookCombinator} from "../src/plugins/hooks/combinators/HookCombinator.sol";
import {PaymentIndexRecorderHook} from "../src/plugins/hooks/PaymentIndexRecorderHook.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";

/// @notice Read-only prediction of canonical CREATE2 addresses for x402r-authored contracts.
/// @dev Run: `forge script script/PredictAddresses.s.sol -vvv` (no broadcast).
///      Reproduces the exact addresses that `DeployX402r` will land at, given the locked
///      toolchain (foundry.toml) and the canonical Base `AuthCaptureEscrow` constant. Cross-check
///      this on every developer machine before any rollout — divergent output here is the canary
///      for toolchain drift.
///
///      The escrow address is the canonical Base deployment of `base/commerce-payments at v1.0.0`,
///      not predicted from a salt. The two collectors (ERC3009 and Permit2) are similarly
///      external constants and not part of this script — see the upstream README for their
///      canonical addresses.
///
///      `ProtocolFeeConfig` prediction additionally reads `OWNER_ADDRESS` and `PROTOCOL_FEE_RECIPIENT`
///      from env (same as `DeployX402r.s.sol`). This is the second tool that can recompute the
///      fragmentation-guard pin in `DeployX402r.s.sol::EXPECTED_PROTOCOL_FEE_CONFIG` — divergent
///      output between the two scripts means the hardcode is stale or the env is wrong.
contract PredictAddresses is Create2Deployer {
    /// @notice Canonical Base `AuthCaptureEscrow` (mirror of `DeployX402r.BASE_AUTH_CAPTURE_ESCROW`).
    address internal constant BASE_AUTH_CAPTURE_ESCROW = 0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff;

    function run() external view {
        address escrow = BASE_AUTH_CAPTURE_ESCROW;

        console.log("=== commerce-payments primitives (external, base/commerce-payments at v1.0.0) ===");
        console.log("");
        console.log("AuthCaptureEscrow:        ", escrow);
        console.log("(ERC3009/Permit2 collectors live at canonical Base addresses; see upstream README.)");

        // ---- x402r hook singletons (BUSL) ----
        // PaymentIndexRecorderHook(escrow, hookCombinatorCodehash) is a chain singleton because both
        // constructor args are chain-invariants. Codehash is the runtime keccak256 of the
        // HookCombinator contract — same value on every chain at the locked toolchain.
        bytes32 hookCombinatorCodehash = keccak256(type(HookCombinator).runtimeCode);
        bytes32 paymentIndexHookInitHash = keccak256(
            abi.encodePacked(type(PaymentIndexRecorderHook).creationCode, abi.encode(escrow, hookCombinatorCodehash))
        );
        address paymentIndexHook =
            _predict2("x402r-canonical-v1.0.1::PaymentIndexRecorderHook", paymentIndexHookInitHash);

        console.log("");
        console.log("=== x402r hook singletons (BUSL) ===");
        console.log("");
        console.log("HookCombinator runtime codehash:");
        console.logBytes32(hookCombinatorCodehash);
        console.log("");
        console.log("PaymentIndexRecorderHook(escrow, hookCombinatorCodehash)  [salt: x402r-canonical-v1.0.1]");
        console.log("  initCodeHash:");
        console.logBytes32(paymentIndexHookInitHash);
        console.log("  predicted:  ", paymentIndexHook);

        // ProtocolFeeConfig is the fragmentation-guard pin in DeployX402r.s.sol. It does not depend
        // on the escrow, so it stays at the v1 salt namespace and its address is unchanged from the
        // existing canonical deployments tracked in `deployments/canonical.json`. Both ctor args
        // (OWNER_ADDRESS, PROTOCOL_FEE_RECIPIENT) come from env so this prediction is the only
        // independent recomputation path of `EXPECTED_PROTOCOL_FEE_CONFIG` short of running the
        // deploy script itself. Cross-check before broadcasting on a new chain.
        address canonicalOwner = vm.envAddress("OWNER_ADDRESS");
        address canonicalFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        bytes32 protocolFeeConfigInitHash = keccak256(
            abi.encodePacked(
                type(ProtocolFeeConfig).creationCode, abi.encode(address(0), canonicalFeeRecipient, canonicalOwner)
            )
        );
        address protocolFeeConfig = _predict2("x402r-canonical-v1::ProtocolFeeConfig", protocolFeeConfigInitHash);

        console.log("");
        console.log("ProtocolFeeConfig(address(0), PROTOCOL_FEE_RECIPIENT, OWNER_ADDRESS)  [salt: x402r-canonical-v1]");
        console.log("  OWNER_ADDRESS:         ", canonicalOwner);
        console.log("  PROTOCOL_FEE_RECIPIENT:", canonicalFeeRecipient);
        console.log("  initCodeHash:");
        console.logBytes32(protocolFeeConfigInitHash);
        console.log("  predicted:  ", protocolFeeConfig);
    }
}
