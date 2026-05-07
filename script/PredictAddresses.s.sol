// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {Create2Deployer} from "./deploy/Create2Deployer.sol";

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ERC3009PaymentCollector} from "commerce-payments/collectors/ERC3009PaymentCollector.sol";
import {Permit2PaymentCollector} from "commerce-payments/collectors/Permit2PaymentCollector.sol";

import {HookCombinator} from "../src/plugins/hooks/combinators/HookCombinator.sol";
import {PaymentIndexRecorderHook} from "../src/plugins/hooks/PaymentIndexRecorderHook.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";

/// @notice Read-only prediction of canonical CREATE2 addresses.
/// @dev Run: `forge script script/PredictAddresses.s.sol -vvv` (no broadcast).
///      Reproduces the exact addresses that `DeployCommercePayments` and `DeployX402r` will
///      land at, given the locked toolchain (foundry.toml) and pinned `lib/commerce-payments`
///      submodule. Cross-check this on every developer machine before any rollout — divergent
///      output here is the canary for toolchain drift.
///
///      `ProtocolFeeConfig` prediction additionally reads `OWNER_ADDRESS` and `PROTOCOL_FEE_RECIPIENT`
///      from env (same as `DeployX402r.s.sol`). This is the second tool that can recompute the
///      fragmentation-guard pin in `DeployX402r.s.sol::EXPECTED_PROTOCOL_FEE_CONFIG` — divergent
///      output between the two scripts means the hardcode is stale or the env is wrong.
contract PredictAddresses is Create2Deployer {
    address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function run() external view {
        // ---- commerce-payments primitives (MIT, vendored from base/commerce-payments@v1.0.0) ----
        bytes32 escrowInitHash = keccak256(type(AuthCaptureEscrow).creationCode);
        address escrow = _predict2("commerce-payments::v1::AuthCaptureEscrow", escrowInitHash);

        bytes32 erc3009InitHash =
            keccak256(abi.encodePacked(type(ERC3009PaymentCollector).creationCode, abi.encode(escrow, MULTICALL3)));
        address erc3009 = _predict2("commerce-payments::v1::ERC3009PaymentCollector", erc3009InitHash);

        bytes32 permit2InitHash = keccak256(
            abi.encodePacked(type(Permit2PaymentCollector).creationCode, abi.encode(escrow, PERMIT2, MULTICALL3))
        );
        address permit2Collector = _predict2("commerce-payments::v1::Permit2PaymentCollector", permit2InitHash);

        console.log("=== commerce-payments primitives (MIT) ===");
        console.log("");
        console.log("AuthCaptureEscrow");
        console.log("  initCodeHash:");
        console.logBytes32(escrowInitHash);
        console.log("  predicted:  ", escrow);
        console.log("");
        console.log("ERC3009PaymentCollector(escrow, MULTICALL3)");
        console.log("  initCodeHash:");
        console.logBytes32(erc3009InitHash);
        console.log("  predicted:  ", erc3009);
        console.log("");
        console.log("Permit2PaymentCollector(escrow, PERMIT2, MULTICALL3)");
        console.log("  initCodeHash:");
        console.logBytes32(permit2InitHash);
        console.log("  predicted:  ", permit2Collector);

        // ---- x402r hook singletons (BUSL) ----
        // PaymentIndexRecorderHook(escrow, hookCombinatorCodehash) is a chain singleton because both
        // constructor args are chain-invariants. Codehash is the runtime keccak256 of the
        // HookCombinator contract — same value on every chain at the locked toolchain.
        bytes32 hookCombinatorCodehash = keccak256(type(HookCombinator).runtimeCode);
        bytes32 paymentIndexHookInitHash = keccak256(
            abi.encodePacked(type(PaymentIndexRecorderHook).creationCode, abi.encode(escrow, hookCombinatorCodehash))
        );
        address paymentIndexHook = _predict2("x402r-canonical-v1::PaymentIndexRecorderHook", paymentIndexHookInitHash);

        console.log("");
        console.log("=== x402r hook singletons (BUSL) ===");
        console.log("");
        console.log("HookCombinator runtime codehash:");
        console.logBytes32(hookCombinatorCodehash);
        console.log("");
        console.log("PaymentIndexRecorderHook(escrow, hookCombinatorCodehash)");
        console.log("  initCodeHash:");
        console.logBytes32(paymentIndexHookInitHash);
        console.log("  predicted:  ", paymentIndexHook);

        // ProtocolFeeConfig is the fragmentation-guard pin in DeployX402r.s.sol. Both ctor args
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
        console.log("ProtocolFeeConfig(address(0), PROTOCOL_FEE_RECIPIENT, OWNER_ADDRESS)");
        console.log("  OWNER_ADDRESS:         ", canonicalOwner);
        console.log("  PROTOCOL_FEE_RECIPIENT:", canonicalFeeRecipient);
        console.log("  initCodeHash:");
        console.logBytes32(protocolFeeConfigInitHash);
        console.log("  predicted:  ", protocolFeeConfig);
    }
}
