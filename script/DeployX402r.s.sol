// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {Create2Deployer} from "./deploy/Create2Deployer.sol";

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

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
import {HookCombinatorFactory} from "../src/plugins/hooks/combinators/HookCombinatorFactory.sol";
import {RefundRequestFactory} from "../src/requests/refund/RefundRequestFactory.sol";
import {ReceiverRefundCollector} from "../src/collectors/ReceiverRefundCollector.sol";
import {RefundRequestEvidenceFactory} from "../src/evidence/RefundRequestEvidenceFactory.sol";

/**
 * @title DeployX402r
 * @notice Deterministic CREATE2 deployment of x402r-authored contracts (BUSL-1.1) at canonical
 *         addresses. Depends on the upstream `base/commerce-payments` primitives (MIT) being
 *         already deployed via `script/DeployCommercePayments.s.sol`.
 *
 * @dev Salt namespace: `x402r-canonical-v1::<ContractName>`.
 *
 *      The escrow address is predicted from the canonical CREATE2 derivation (label
 *      `commerce-payments::v1::AuthCaptureEscrow` + locked upstream initCode at the v1.0.0
 *      submodule pin). The script asserts the predicted address has code; if not, run
 *      `DeployCommercePayments.s.sol` first.
 *
 *      Set CANONICAL_OWNER and CANONICAL_FEE_RECIPIENT below before running. Both are pinned
 *      constants, not env vars: any change moves the CREATE2 addresses of the contracts that
 *      take them as constructor args (ProtocolFeeConfig and everything downstream).
 *
 *      Usage:
 *        forge script script/DeployX402r.s.sol --rpc-url <RPC> --broadcast --verify -vvv
 */
contract DeployX402r is Create2Deployer {
    // ---- Canonical x402r EOAs ----
    // TBD: Replace with production multisig addresses BEFORE running this script.
    // Any change here moves the CREATE2 addresses of contracts that take these as
    // constructor args (ProtocolFeeConfig, PaymentOperatorFactory, and everything
    // downstream of them).
    //
    // DO NOT broadcast with the placeholder address(0) — the run() pre-flight require()s
    // below fail-fast on broadcast, but more fundamentally: the canonical address bakes
    // these constructor args in immutably, so deploying with a placeholder permanently
    // pins the wrong owner at the canonical address on that chain.
    address constant CANONICAL_OWNER = address(0);
    address constant CANONICAL_FEE_RECIPIENT = address(0);

    function run() external {
        require(CANONICAL_OWNER != address(0), "Set CANONICAL_OWNER before deploying");
        require(CANONICAL_FEE_RECIPIENT != address(0), "Set CANONICAL_FEE_RECIPIENT before deploying");

        // Predict + assert the upstream escrow is already deployed.
        address escrow =
            _predict2("commerce-payments::v1::AuthCaptureEscrow", keccak256(type(AuthCaptureEscrow).creationCode));
        require(escrow.code.length > 0, "AuthCaptureEscrow not deployed - run DeployCommercePayments.s.sol first");

        uint256 deployerPk = vm.envUint("PRIVATE_KEY");

        console.log("\n========================================");
        console.log("  x402r BUSL contracts (CREATE2)");
        console.log("========================================");
        console.log("Chain ID:           ", block.chainid);
        console.log("Deployer:           ", vm.addr(deployerPk));
        console.log("Owner:              ", CANONICAL_OWNER);
        console.log("Fee Recipient:      ", CANONICAL_FEE_RECIPIENT);
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
                type(ProtocolFeeConfig).creationCode, abi.encode(address(0), CANONICAL_FEE_RECIPIENT, CANONICAL_OWNER)
            )
        );
        console.log("ProtocolFeeConfig:", protocolFeeConfig);

        address paymentOperatorFactory = _deploy2(
            "x402r-canonical-v1::PaymentOperatorFactory",
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
            "x402r-canonical-v1::EscrowPeriodFactory",
            abi.encodePacked(type(EscrowPeriodFactory).creationCode, abi.encode(escrow))
        );
        console.log("EscrowPeriodFactory:", escrowPeriodFactory);

        address freezeFactory = _deploy2(
            "x402r-canonical-v1::FreezeFactory", abi.encodePacked(type(FreezeFactory).creationCode, abi.encode(escrow))
        );
        console.log("FreezeFactory:", freezeFactory);

        // =============================================
        // 5. Refund-side
        // =============================================
        console.log("\n--- 5. Refund-side ---");

        address refundReqFactory = _deploy2(
            "x402r-canonical-v1::RefundRequestFactory",
            abi.encodePacked(type(RefundRequestFactory).creationCode, abi.encode(escrow))
        );
        console.log("RefundRequestFactory:", refundReqFactory);

        address receiverRefundCollector = _deploy2(
            "x402r-canonical-v1::ReceiverRefundCollector",
            abi.encodePacked(type(ReceiverRefundCollector).creationCode, abi.encode(escrow))
        );
        console.log("ReceiverRefundCollector:", receiverRefundCollector);

        address refundRequestEvidenceFactory = _deploy2(
            "x402r-canonical-v1::RefundRequestEvidenceFactory", type(RefundRequestEvidenceFactory).creationCode
        );
        console.log("RefundRequestEvidenceFactory:", refundRequestEvidenceFactory);

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
        console.log("========================================");
    }
}
