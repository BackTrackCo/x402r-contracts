// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {Create2Deployer} from "./deploy/Create2Deployer.sol";

import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {SignatureConditionFactory} from "../src/plugins/conditions/access/signature/SignatureConditionFactory.sol";
import {PayerCondition} from "../src/plugins/conditions/access/PayerCondition.sol";
import {ReceiverCondition} from "../src/plugins/conditions/access/ReceiverCondition.sol";
import {AlwaysTrueCondition} from "../src/plugins/conditions/access/AlwaysTrueCondition.sol";
import {EscrowPeriodFactory} from "../src/plugins/escrow-period/EscrowPeriodFactory.sol";
import {FreezeFactory} from "../src/plugins/freeze/FreezeFactory.sol";
import {StaticFeeCalculatorFactory} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol";
import {
    StaticAddressConditionFactory
} from "../src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol";
import {AndConditionFactory} from "../src/plugins/conditions/combinators/AndConditionFactory.sol";
import {OrConditionFactory} from "../src/plugins/conditions/combinators/OrConditionFactory.sol";
import {NotConditionFactory} from "../src/plugins/conditions/combinators/NotConditionFactory.sol";
import {HookCombinator} from "../src/plugins/hooks/combinators/HookCombinator.sol";
import {HookCombinatorFactory} from "../src/plugins/hooks/combinators/HookCombinatorFactory.sol";
import {PaymentIndexRecorderHook} from "../src/plugins/hooks/PaymentIndexRecorderHook.sol";
import {RefundRequestFactory} from "../src/requests/refund/RefundRequestFactory.sol";
import {ReceiverRefundCollector} from "../src/collectors/ReceiverRefundCollector.sol";
import {RefundRequestEvidenceFactory} from "../src/evidence/RefundRequestEvidenceFactory.sol";

/**
 * @title DeployX402r
 * @notice Deterministic CREATE2 deployment of x402r-authored contracts (BUSL-1.1) bound to the
 *         canonical, audited `base/commerce-payments at v1.0.0` deployment of `AuthCaptureEscrow`.
 *
 * @dev Salt namespaces:
 *        - `x402r-canonical-v1::*`     — escrow-independent contracts (ProtocolFeeConfig,
 *                                        condition singletons, ctor-arg-free factories,
 *                                        RefundRequestEvidenceFactory). Already live on the
 *                                        chains listed in `deployments/canonical.json`.
 *        - `x402r-canonical-v1.0.1::*` — escrow-dependent contracts whose source is unchanged from v1
 *                                        (EscrowPeriodFactory, FreezeFactory, RefundRequestFactory,
 *                                        ReceiverRefundCollector, PaymentIndexRecorderHook).
 *                                        v1.0.1 signals: same source code as v1, rebound to the
 *                                        canonical Base escrow at `BASE_AUTH_CAPTURE_ESCROW`.
 *        - `x402r-canonical-v1.0.2::*` — PaymentOperatorFactory only. The factory embeds
 *                                        `type(PaymentOperator).creationCode`, so the operator's
 *                                        6-arg `charge` change shifts the factory's initCodeHash.
 *                                        v1.0.2 signals: factory source changed (not just rebound),
 *                                        so its address must not collide with the v1.0.1 label.
 *
 *      Escrow source: hardcoded to the canonical Base deployment of `AuthCaptureEscrow` from
 *      `base/commerce-payments at v1.0.0` (see the upstream README). The script asserts the address
 *      has code on the target chain; if not, the canonical primitives are not yet deployed there
 *      and x402r cannot bring up at v1.0.1 on that chain (today: Base mainnet + Base Sepolia only).
 *
 *      Required env vars (alongside `PRIVATE_KEY`):
 *        - `OWNER_ADDRESS`           — owner of `ProtocolFeeConfig` (controls the 7-day timelocked
 *                                      fee-calculator swap). Address-typed.
 *        - `PROTOCOL_FEE_RECIPIENT`  — recipient of protocol fees. Address-typed.
 *
 *      Both addresses are baked immutably into `ProtocolFeeConfig`'s ctor args and so move the
 *      CREATE2 address of `ProtocolFeeConfig` itself. Change them and the v1 namespace shifts —
 *      `_deploy2` is idempotent across re-runs at the *same* values, but a different
 *      `OWNER_ADDRESS` lands at a fresh address on the same chain.
 *
 *      Usage:
 *        forge script script/DeployX402r.s.sol --rpc-url <RPC> --broadcast --verify -vvv
 */
contract DeployX402r is Create2Deployer {
    /// @notice Canonical `AuthCaptureEscrow` from `base/commerce-payments at v1.0.0`, deployed by
    ///         Base at this address on Base mainnet (8453) and Base Sepolia (84532).
    /// @dev    Source of truth: https://github.com/base/commerce-payments README. The CREATE2
    ///         derivation is internal to Base's deploy process; we treat this address as an
    ///         external constant. Verify on-chain with `cast code` before broadcasting on a new
    ///         chain — the pre-flight assert below requires `code.length > 0`.
    address internal constant BASE_AUTH_CAPTURE_ESCROW = 0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff;

    /// @notice EXTCODEHASH of the canonical `AuthCaptureEscrow` at `BASE_AUTH_CAPTURE_ESCROW`.
    /// @dev `escrow.code.length > 0` only proves *something* is deployed there; it does not prove
    ///      it's the genuine audited escrow. Since this address is baked as a ctor arg into all six
    ///      v1.0.1 contracts, a future chain where `BASE_AUTH_CAPTURE_ESCROW` resolves to a
    ///      *different* contract would silently fragment the entire namespace. Pinning the codehash
    ///      closes the "wrong contract already lives there" case that the length check cannot.
    ///
    ///      Verified identical on Base mainnet (8453) and Base Sepolia (84532) via
    ///      `cast codehash 0xBdEA0D1bcC5966192B070Fdf62aB4EF5b4420cff --rpc-url <base|base-sepolia>`.
    ///      Re-derive before broadcasting on any new chain — the audited bytecode is chain-invariant,
    ///      so a mismatch means the address is occupied by something else.
    bytes32 internal constant EXPECTED_ESCROW_CODEHASH =
        0x06c981228c864c5e6e57b57a98092e5b57557839db5a71c20b9435e687ff4b20;

    /// @notice Canonical `ProtocolFeeConfig` CREATE2 address derived from the live owner/recipient.
    /// @dev Hardcoded as a fragmentation guard: `ProtocolFeeConfig`'s ctor takes the env-provided
    ///      `OWNER_ADDRESS` and `PROTOCOL_FEE_RECIPIENT`, and every contract downstream of it bakes
    ///      this address in. A typo in either env var silently lands the entire namespace at fresh
    ///      addresses on this chain, fragmenting from the chains that already deployed. The
    ///      pre-flight assert below recomputes the predicted address with the current env values
    ///      and reverts if it doesn't match this canonical pin.
    ///
    ///      Audit trail: see `deployments/canonical.json` for the chain IDs and on-chain deploy
    ///      tx hashes that produced this address. Independently reproducible by running
    ///      `forge script script/PredictAddresses.s.sol -vvv` with the canonical env vars set.
    ///
    ///      Caveat on "independent": `PredictAddresses` and this script both read `OWNER_ADDRESS` /
    ///      `PROTOCOL_FEE_RECIPIENT` from the same env, so the recompute is independent only w.r.t.
    ///      this hardcoded pin (catches a stale constant or toolchain drift), NOT w.r.t. the env —
    ///      a wrong env value set in both produces matching (wrong) output. The pin is the trust
    ///      anchor; the env is not cross-checked.
    address internal constant EXPECTED_PROTOCOL_FEE_CONFIG = 0xBe2d24614F339a1eB103A399F93AA2a39Ca815Bc;

    /// @notice Canonical CREATE2 pins for the six escrow-dependent contracts (five at v1.0.1, plus
    ///         PaymentOperatorFactory at v1.0.2 — see EXPECTED_PAYMENT_OPERATOR_FACTORY).
    /// @dev Source of truth: `deployments/canonical-v1.0.1.json` (five) and
    ///      `deployments/canonical-v1.0.2.json` (factory), re-derived by
    ///      `test/script/CanonicalAddresses.t.sol`. Unlike `EXPECTED_PROTOCOL_FEE_CONFIG`, these are
    ///      env-INDEPENDENT: every one is a pure function of the `BASE_AUTH_CAPTURE_ESCROW` ctor arg
    ///      (plus `EXPECTED_PROTOCOL_FEE_CONFIG` for the operator factory and the `HookCombinator`
    ///      runtime codehash for the hook) and the locked toolchain. The pre-flight guard in `run()`
    ///      predicts each and reverts on mismatch, so escrow rebinding or toolchain drift aborts the
    ///      run before any contract is broadcast — extending the single-contract `ProtocolFeeConfig`
    ///      guard to cover the whole escrow-dependent namespace.
    /// @dev v1.0.2 namespace: PaymentOperatorFactory embeds `type(PaymentOperator).creationCode`, so
    ///      the operator's 6-arg `charge` change (PR #40) shifts the factory's initCodeHash and CREATE2
    ///      address. The other five escrow-dependent contracts are unaffected and stay at v1.0.1.
    address internal constant EXPECTED_PAYMENT_OPERATOR_FACTORY = 0xc24153B7ED8DC03e551F29DDEeA5CadFe57e2716;
    address internal constant EXPECTED_ESCROW_PERIOD_FACTORY = 0xe72D2014ebC48F1d92521e8629574918E8030548;
    address internal constant EXPECTED_FREEZE_FACTORY = 0xeC092cf1215DB44af0Abe87c1157E304FEa5d0Eb;
    address internal constant EXPECTED_REFUND_REQUEST_FACTORY = 0xe971C674fD5c3462023f3F891dF6289DFbC9CEFC;
    address internal constant EXPECTED_RECEIVER_REFUND_COLLECTOR = 0x88C9826dFA17Ad9d3a726015C667dD995394D341;
    address internal constant EXPECTED_PAYMENT_INDEX_RECORDER_HOOK = 0x358ECA14fFD51e63D2Bb8DDE3aBAA14f8D5274C3;

    function run() external {
        address canonicalOwner = vm.envAddress("OWNER_ADDRESS");
        address canonicalFeeRecipient = vm.envAddress("PROTOCOL_FEE_RECIPIENT");
        require(canonicalOwner != address(0), "OWNER_ADDRESS must be non-zero");
        require(canonicalFeeRecipient != address(0), "PROTOCOL_FEE_RECIPIENT must be non-zero");

        // Assert the canonical Base AuthCaptureEscrow is deployed on this chain. If not, Base has
        // not extended commerce-payments to this chain yet and x402r v1.0.1 cannot bring up here.
        address escrow = BASE_AUTH_CAPTURE_ESCROW;
        require(
            escrow.code.length > 0,
            "AuthCaptureEscrow not deployed on this chain - canonical base/commerce-payments at v1.0.0 missing"
        );
        // Codehash pin: prove the deployed code IS the genuine audited AuthCaptureEscrow, not just
        // that *some* contract occupies the address. The length check above fails safe on an empty
        // address; this additionally closes the "wrong contract already lives there" case on a chain
        // where 0xBdEA0D... resolves to something other than the canonical escrow.
        require(
            escrow.codehash == EXPECTED_ESCROW_CODEHASH,
            "BASE_AUTH_CAPTURE_ESCROW codehash mismatch - address is not the canonical audited AuthCaptureEscrow"
        );

        // Fragmentation guard: predict ProtocolFeeConfig with the env-provided owner/recipient and
        // assert it matches the canonical pin. A typo in either env var would otherwise land at a
        // fresh address and cascade through every downstream contract.
        address predictedProtocolFeeConfig = _predict2(
            "x402r-canonical-v1::ProtocolFeeConfig",
            keccak256(
                abi.encodePacked(
                    type(ProtocolFeeConfig).creationCode, abi.encode(address(0), canonicalFeeRecipient, canonicalOwner)
                )
            )
        );
        require(
            predictedProtocolFeeConfig == EXPECTED_PROTOCOL_FEE_CONFIG,
            "OWNER_ADDRESS / PROTOCOL_FEE_RECIPIENT do not match the canonical namespace - check env; intentional owner rotation requires bumping salt to x402r-canonical-v2::*"
        );

        // Extend the fragmentation guard across the whole escrow-dependent namespace. Each of the six
        // escrow-dependent addresses is env-independent (a pure function of `escrow`, plus the operator factory's
        // `protocolFeeConfig` arg and the hook's HookCombinator codehash), so this pre-flight predicts
        // each and reverts on any drift before `vm.startBroadcast` — nothing is broadcast if a single
        // pin is off, vs. the prior state where only ProtocolFeeConfig was guarded and the other six
        // could silently land at fresh addresses.
        bytes32 hookCombinatorCodehash = keccak256(type(HookCombinator).runtimeCode);
        _assertCanonicalPin(
            "x402r-canonical-v1.0.2::PaymentOperatorFactory",
            keccak256(
                abi.encodePacked(
                    type(PaymentOperatorFactory).creationCode, abi.encode(escrow, predictedProtocolFeeConfig)
                )
            ),
            EXPECTED_PAYMENT_OPERATOR_FACTORY
        );
        _assertCanonicalPin(
            "x402r-canonical-v1.0.1::EscrowPeriodFactory",
            keccak256(abi.encodePacked(type(EscrowPeriodFactory).creationCode, abi.encode(escrow))),
            EXPECTED_ESCROW_PERIOD_FACTORY
        );
        _assertCanonicalPin(
            "x402r-canonical-v1.0.1::FreezeFactory",
            keccak256(abi.encodePacked(type(FreezeFactory).creationCode, abi.encode(escrow))),
            EXPECTED_FREEZE_FACTORY
        );
        _assertCanonicalPin(
            "x402r-canonical-v1.0.1::RefundRequestFactory",
            keccak256(abi.encodePacked(type(RefundRequestFactory).creationCode, abi.encode(escrow))),
            EXPECTED_REFUND_REQUEST_FACTORY
        );
        _assertCanonicalPin(
            "x402r-canonical-v1.0.1::ReceiverRefundCollector",
            keccak256(abi.encodePacked(type(ReceiverRefundCollector).creationCode, abi.encode(escrow))),
            EXPECTED_RECEIVER_REFUND_COLLECTOR
        );
        _assertCanonicalPin(
            "x402r-canonical-v1.0.1::PaymentIndexRecorderHook",
            keccak256(
                abi.encodePacked(
                    type(PaymentIndexRecorderHook).creationCode, abi.encode(escrow, hookCombinatorCodehash)
                )
            ),
            EXPECTED_PAYMENT_INDEX_RECORDER_HOOK
        );

        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        require(deployerPk != 0, "PRIVATE_KEY must be non-zero");

        console.log("\n========================================");
        console.log("  x402r BUSL contracts (CREATE2)");
        console.log("========================================");
        console.log("Chain ID:           ", block.chainid);
        console.log("Deployer:           ", vm.addr(deployerPk));
        console.log("Owner:              ", canonicalOwner);
        console.log("Fee Recipient:      ", canonicalFeeRecipient);
        console.log("AuthCaptureEscrow:  ", escrow);

        vm.startBroadcast(deployerPk);

        // =============================================
        // 1. x402r protocol infrastructure
        // =============================================
        console.log("\n--- 1. x402r protocol infrastructure ---");

        // ProtocolFeeConfig deploys with calculator = address(0) (protocol fees disabled by
        // default; getProtocolFeeBps returns 0 when calculator is unset). Owner can swap to a
        // real calculator via 7-day timelock per chain after deploy.
        address protocolFeeConfig = _deploy2(
            "x402r-canonical-v1::ProtocolFeeConfig",
            abi.encodePacked(
                type(ProtocolFeeConfig).creationCode, abi.encode(address(0), canonicalFeeRecipient, canonicalOwner)
            )
        );
        console.log("ProtocolFeeConfig:", protocolFeeConfig);

        address paymentOperatorFactory = _deploy2(
            "x402r-canonical-v1.0.2::PaymentOperatorFactory",
            abi.encodePacked(type(PaymentOperatorFactory).creationCode, abi.encode(escrow, protocolFeeConfig))
        );
        console.log("PaymentOperatorFactory:", paymentOperatorFactory);

        // =============================================
        // 2. Plugin singletons (no ctor args)
        // =============================================
        console.log("\n--- 2. Plugin singletons ---");

        address payerCondition = _deploy2("x402r-canonical-v1::PayerCondition", type(PayerCondition).creationCode);
        console.log("PayerCondition:", payerCondition);

        address receiverCondition =
            _deploy2("x402r-canonical-v1::ReceiverCondition", type(ReceiverCondition).creationCode);
        console.log("ReceiverCondition:", receiverCondition);

        address alwaysTrueCondition =
            _deploy2("x402r-canonical-v1::AlwaysTrueCondition", type(AlwaysTrueCondition).creationCode);
        console.log("AlwaysTrueCondition:", alwaysTrueCondition);

        // =============================================
        // 3. Plugin factories
        // =============================================
        console.log("\n--- 3. Plugin factories ---");

        address sigCondFactory =
            _deploy2("x402r-canonical-v1::SignatureConditionFactory", type(SignatureConditionFactory).creationCode);
        console.log("SignatureConditionFactory:", sigCondFactory);

        address staticAddrCondFactory = _deploy2(
            "x402r-canonical-v1::StaticAddressConditionFactory", type(StaticAddressConditionFactory).creationCode
        );
        console.log("StaticAddressConditionFactory:", staticAddrCondFactory);

        address andFactory = _deploy2("x402r-canonical-v1::AndConditionFactory", type(AndConditionFactory).creationCode);
        console.log("AndConditionFactory:", andFactory);

        address orFactory = _deploy2("x402r-canonical-v1::OrConditionFactory", type(OrConditionFactory).creationCode);
        console.log("OrConditionFactory:", orFactory);

        address notFactory = _deploy2("x402r-canonical-v1::NotConditionFactory", type(NotConditionFactory).creationCode);
        console.log("NotConditionFactory:", notFactory);

        address hookCombFactory =
            _deploy2("x402r-canonical-v1::HookCombinatorFactory", type(HookCombinatorFactory).creationCode);
        console.log("HookCombinatorFactory:", hookCombFactory);

        address staticFeeCalcFactory =
            _deploy2("x402r-canonical-v1::StaticFeeCalculatorFactory", type(StaticFeeCalculatorFactory).creationCode);
        console.log("StaticFeeCalculatorFactory:", staticFeeCalcFactory);

        // =============================================
        // 4. Per-payment factories (escrow-bound)
        // =============================================
        console.log("\n--- 4. Per-payment factories ---");

        address escrowPeriodFactory = _deploy2(
            "x402r-canonical-v1.0.1::EscrowPeriodFactory",
            abi.encodePacked(type(EscrowPeriodFactory).creationCode, abi.encode(escrow))
        );
        console.log("EscrowPeriodFactory:", escrowPeriodFactory);

        address freezeFactory = _deploy2(
            "x402r-canonical-v1.0.1::FreezeFactory",
            abi.encodePacked(type(FreezeFactory).creationCode, abi.encode(escrow))
        );
        console.log("FreezeFactory:", freezeFactory);

        // =============================================
        // 5. Refund-side
        // =============================================
        console.log("\n--- 5. Refund-side ---");

        address refundReqFactory = _deploy2(
            "x402r-canonical-v1.0.1::RefundRequestFactory",
            abi.encodePacked(type(RefundRequestFactory).creationCode, abi.encode(escrow))
        );
        console.log("RefundRequestFactory:", refundReqFactory);

        address receiverRefundCollector = _deploy2(
            "x402r-canonical-v1.0.1::ReceiverRefundCollector",
            abi.encodePacked(type(ReceiverRefundCollector).creationCode, abi.encode(escrow))
        );
        console.log("ReceiverRefundCollector:", receiverRefundCollector);

        address refundRequestEvidenceFactory = _deploy2(
            "x402r-canonical-v1::RefundRequestEvidenceFactory", type(RefundRequestEvidenceFactory).creationCode
        );
        console.log("RefundRequestEvidenceFactory:", refundRequestEvidenceFactory);

        // =============================================
        // 6. Hook singletons
        // =============================================
        // PaymentIndexRecorderHook can be a chain singleton because both of its constructor args are
        // chain-invariants:
        //   - escrow:        canonical AuthCaptureEscrow CREATE2 address
        //   - authorizedCodehash: HookCombinator runtime codehash, which is identical across
        //                    every HookCombinator instance regardless of stored hooks (storage
        //                    slots, not bytecode, hold the per-instance config). The codehash
        //                    is reproducible from the locked toolchain — see PredictAddresses.
        // Gating PaymentIndexRecorderHook on the canonical HookCombinator codehash means any operator
        // routing post-action through HookCombinator can reuse this one deployment.
        //
        // Versioning footgun: any future change to `HookCombinator`'s runtime bytecode shifts the
        // codehash and so requires a new salt label (e.g. `x402r-canonical-v2::*`) and a fresh
        // `PaymentIndexRecorderHook` deploy. The existing hook will reject calls from the new
        // combinator (codehash gate fails). When bumping HookCombinator, bump the namespace label
        // too.
        console.log("\n--- 6. Hook singletons ---");

        // hookCombinatorCodehash already computed in the pre-flight fragmentation guard above.
        console.log("HookCombinator codehash:");
        console.logBytes32(hookCombinatorCodehash);

        address paymentIndexHook = _deploy2(
            "x402r-canonical-v1.0.1::PaymentIndexRecorderHook",
            abi.encodePacked(type(PaymentIndexRecorderHook).creationCode, abi.encode(escrow, hookCombinatorCodehash))
        );
        console.log("PaymentIndexRecorderHook:", paymentIndexHook);

        vm.stopBroadcast();

        // =============================================
        // Summary
        // =============================================
        console.log("\n========================================");
        console.log("  X402R DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("  ProtocolFeeConfig:             ", protocolFeeConfig);
        console.log("  PaymentOperatorFactory:        ", paymentOperatorFactory);
        console.log("");
        console.log("  PayerCondition:                ", payerCondition);
        console.log("  ReceiverCondition:             ", receiverCondition);
        console.log("  AlwaysTrueCondition:           ", alwaysTrueCondition);
        console.log("  SignatureConditionFactory:     ", sigCondFactory);
        console.log("  StaticAddressConditionFactory: ", staticAddrCondFactory);
        console.log("  AndConditionFactory:           ", andFactory);
        console.log("  OrConditionFactory:            ", orFactory);
        console.log("  NotConditionFactory:           ", notFactory);
        console.log("  HookCombinatorFactory:         ", hookCombFactory);
        console.log("  StaticFeeCalculatorFactory:    ", staticFeeCalcFactory);
        console.log("  EscrowPeriodFactory:           ", escrowPeriodFactory);
        console.log("  FreezeFactory:                 ", freezeFactory);
        console.log("");
        console.log("  RefundRequestFactory:          ", refundReqFactory);
        console.log("  ReceiverRefundCollector:       ", receiverRefundCollector);
        console.log("  RefundRequestEvidenceFactory:  ", refundRequestEvidenceFactory);
        console.log("");
        console.log("  PaymentIndexRecorderHook:              ", paymentIndexHook);
        console.log("========================================");
    }

    /// @notice Predict an escrow-dependent address and assert it matches its canonical pin.
    /// @dev Pre-flight only — reverts before any broadcast on escrow rebinding or toolchain drift.
    function _assertCanonicalPin(string memory label, bytes32 initCodeHash, address expected) internal pure {
        require(
            _predict2(label, initCodeHash) == expected,
            string.concat(label, " predicted address drifted from its canonical pin - do not broadcast")
        );
    }
}
