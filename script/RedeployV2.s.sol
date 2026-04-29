// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

// Protocol infrastructure (changed — added nonTransientReentrancyGuardMode)
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";

// Singletons (changed — ICondition.check now takes bytes data)
import {SignatureConditionFactory} from "../src/plugins/conditions/access/signature/SignatureConditionFactory.sol";

// Condition singletons (changed — bytes data param)
import {PayerCondition} from "../src/plugins/conditions/access/PayerCondition.sol";
import {ReceiverCondition} from "../src/plugins/conditions/access/ReceiverCondition.sol";
import {AlwaysTrueCondition} from "../src/plugins/conditions/access/AlwaysTrueCondition.sol";

// Chain-specific conditions (changed — bytes data param)
import {UsdcTvlLimit} from "../src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol";

// Factories (changed — ICondition/IHook data param, RefundRequest refactor)
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

// Additional (changed — RefundRequest IHook refactor, nonce removal)
import {RefundRequestFactory} from "../src/requests/refund/RefundRequestFactory.sol";
import {RefundRequestEvidenceFactory} from "../src/evidence/RefundRequestEvidenceFactory.sol";

/// @notice Minimal interface for CreateX's CREATE3 deployment
interface ICreateX {
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address);
    function computeCreate3Address(bytes32 salt, address deployer) external view returns (address);
}

/**
 * @title RedeployV2
 * @notice Redeploy CHANGED contracts with v2 salt labels.
 *         Unchanged contracts (AuthCaptureEscrow, TokenCollector, ProtocolFeeConfig,
 *         ReceiverRefundCollector) keep their existing CREATE3 addresses.
 *
 * @dev Changed contracts use "-v2" suffix in salt labels to get new addresses.
 *      Set NON_TRANSIENT=true for SKALE (pre-Cancun), false/unset for all other chains.
 *
 * Usage:
 *   USDC_ADDRESS=0x... TVL_LIMIT=100000000000 \
 *   forge script script/RedeployV2.s.sol --rpc-url <RPC> --broadcast --verify -vvvv
 *
 * For SKALE (pre-Cancun):
 *   NON_TRANSIENT=true USDC_ADDRESS=0x... TVL_LIMIT=100000000000 \
 *   forge script script/RedeployV2.s.sol --rpc-url skale-base --broadcast --legacy --slow -vvvv
 */
contract RedeployV2 is Script {
    ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    // =========================================================================
    // Unchanged v1 addresses (same on all chains, already deployed)
    // =========================================================================
    address constant ESCROW = 0xe050bB89eD43BB02d71343063824614A7fb80B77;
    address constant PROTOCOL_FEE_CONFIG = 0x7e868A42a458fa2443b6259419aA6A8a161E08c8;
    address constant RECEIVER_REFUND_COLLECTOR = 0xE5500a38BE45a6C598420fbd7867ac85EC451A07;

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        uint256 tvlLimit = vm.envUint("TVL_LIMIT");
        bool nonTransient = vm.envOr("NON_TRANSIENT", false);

        console.log("\n========================================");
        console.log("  x402r V2 Redeployment (CREATE3)");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", vm.addr(deployerPk));
        console.log("Non-transient mode:", nonTransient);
        console.log("USDC:", usdcAddress);
        console.log("TVL Limit:", tvlLimit);
        console.log("\nUnchanged (v1):");
        console.log("  AuthCaptureEscrow:", ESCROW);
        console.log("  ProtocolFeeConfig:", PROTOCOL_FEE_CONFIG);
        console.log("  ReceiverRefundCollector:", RECEIVER_REFUND_COLLECTOR);

        vm.startBroadcast(deployerPk);

        // =============================================
        // 1. PaymentOperatorFactory (now with nonTransient mode)
        // =============================================
        console.log("\n--- Changed Contracts (v2 salts) ---");

        address paymentOperatorFactory = _deploy3(
            "payment-operator-factory-v2",
            abi.encodePacked(
                type(PaymentOperatorFactory).creationCode, abi.encode(ESCROW, PROTOCOL_FEE_CONFIG, nonTransient)
            )
        );
        console.log("PaymentOperatorFactory:", paymentOperatorFactory);

        // =============================================
        // 2. Singletons
        // =============================================
        address sigCondFactory = _deploy3("sig-condition-factory-v2", type(SignatureConditionFactory).creationCode);
        console.log("SignatureConditionFactory:", sigCondFactory);

        address refundReqFactory = _deploy3(
            "refund-request-factory-v2", abi.encodePacked(type(RefundRequestFactory).creationCode, abi.encode(ESCROW))
        );
        console.log("RefundRequestFactory:", refundReqFactory);

        // =============================================
        // 3. Condition Singletons
        // =============================================
        address payerCondition = _deploy3("payer-condition-v2", type(PayerCondition).creationCode);
        console.log("PayerCondition:", payerCondition);

        address receiverCondition = _deploy3("receiver-condition-v2", type(ReceiverCondition).creationCode);
        console.log("ReceiverCondition:", receiverCondition);

        address alwaysTrueCondition = _deploy3("always-true-condition-v2", type(AlwaysTrueCondition).creationCode);
        console.log("AlwaysTrueCondition:", alwaysTrueCondition);

        address usdcTvlLimit = _deploy3(
            "usdc-tvl-limit-v2",
            abi.encodePacked(type(UsdcTvlLimit).creationCode, abi.encode(ESCROW, usdcAddress, tvlLimit))
        );
        console.log("UsdcTvlLimit:", usdcTvlLimit);

        // =============================================
        // 4. Factories
        // =============================================
        address escrowPeriodFactory = _deploy3(
            "escrow-period-factory-v2", abi.encodePacked(type(EscrowPeriodFactory).creationCode, abi.encode(ESCROW))
        );
        console.log("EscrowPeriodFactory:", escrowPeriodFactory);

        address freezeFactory =
            _deploy3("freeze-factory-v2", abi.encodePacked(type(FreezeFactory).creationCode, abi.encode(ESCROW)));
        console.log("FreezeFactory:", freezeFactory);

        address staticFeeCalcFactory =
            _deploy3("static-fee-calc-factory-v2", type(StaticFeeCalculatorFactory).creationCode);
        console.log("StaticFeeCalculatorFactory:", staticFeeCalcFactory);

        address staticAddrCondFactory =
            _deploy3("static-addr-condition-factory-v2", type(StaticAddressConditionFactory).creationCode);
        console.log("StaticAddressConditionFactory:", staticAddrCondFactory);

        address andFactory = _deploy3("and-condition-factory-v2", type(AndConditionFactory).creationCode);
        console.log("AndConditionFactory:", andFactory);

        address orFactory = _deploy3("or-condition-factory-v2", type(OrConditionFactory).creationCode);
        console.log("OrConditionFactory:", orFactory);

        address notFactory = _deploy3("not-condition-factory-v2", type(NotConditionFactory).creationCode);
        console.log("NotConditionFactory:", notFactory);

        address hookCombFactory = _deploy3("hook-combinator-factory-v2", type(HookCombinatorFactory).creationCode);
        console.log("HookCombinatorFactory:", hookCombFactory);

        // =============================================
        // 5. Additional
        // =============================================
        address refundRequestEvidenceFactory =
            _deploy3("refund-request-evidence-factory-v2", type(RefundRequestEvidenceFactory).creationCode);
        console.log("RefundRequestEvidenceFactory:", refundRequestEvidenceFactory);

        vm.stopBroadcast();

        // =============================================
        // Summary
        // =============================================
        console.log("\n========================================");
        console.log("  V2 DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("  Unchanged (v1 addresses):");
        console.log("    authCaptureEscrow:", ESCROW);
        console.log("    protocolFeeConfig:", PROTOCOL_FEE_CONFIG);
        console.log("    receiverRefundCollector:", RECEIVER_REFUND_COLLECTOR);
        console.log("  Changed (v2 addresses):");
        console.log("    paymentOperatorFactory:", paymentOperatorFactory);
        console.log("    signatureConditionFactory:", sigCondFactory);
        console.log("    refundRequestFactory:", refundReqFactory);
        console.log("    payerCondition:", payerCondition);
        console.log("    receiverCondition:", receiverCondition);
        console.log("    alwaysTrueCondition:", alwaysTrueCondition);
        console.log("    usdcTvlLimit:", usdcTvlLimit);
        console.log("    escrowPeriodFactory:", escrowPeriodFactory);
        console.log("    freezeFactory:", freezeFactory);
        console.log("    staticFeeCalculatorFactory:", staticFeeCalcFactory);
        console.log("    staticAddressConditionFactory:", staticAddrCondFactory);
        console.log("    andConditionFactory:", andFactory);
        console.log("    orConditionFactory:", orFactory);
        console.log("    notConditionFactory:", notFactory);
        console.log("    hookCombinatorFactory:", hookCombFactory);
        console.log("    refundRequestEvidenceFactory:", refundRequestEvidenceFactory);
        console.log("    nonTransientMode:", nonTransient);
        console.log("========================================");
    }

    function _deploy3(string memory label, bytes memory initCode) internal returns (address deployed) {
        bytes32 salt = bytes32(abi.encodePacked(msg.sender, bytes1(0x00), bytes11(keccak256(bytes(label)))));
        deployed = CREATEX.deployCreate3(salt, initCode);
    }
}
