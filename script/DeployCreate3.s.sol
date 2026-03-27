// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console} from "forge-std/Script.sol";
import {Create3Deployer} from "./deploy/Create3Deployer.sol";

// Core (commerce-payments)
// On Shanghai profile, ReentrancyGuardTransient is remapped to SSTORE-only drop-in
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ERC3009PaymentCollector} from "commerce-payments/collectors/ERC3009PaymentCollector.sol";

// Protocol infrastructure
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculator.sol";

// Singletons
import {ArbiterRegistry} from "../src/registry/ArbiterRegistry.sol";
import {SignatureConditionFactory} from "../src/plugins/conditions/access/signature/SignatureConditionFactory.sol";

// Condition singletons
import {PayerCondition} from "../src/plugins/conditions/access/PayerCondition.sol";
import {ReceiverCondition} from "../src/plugins/conditions/access/ReceiverCondition.sol";
import {AlwaysTrueCondition} from "../src/plugins/conditions/access/AlwaysTrueCondition.sol";

// Chain-specific conditions
import {UsdcTvlLimit} from "../src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol";

// Factories
import {EscrowPeriodFactory} from "../src/plugins/escrow-period/EscrowPeriodFactory.sol";
import {FreezeFactory} from "../src/plugins/freeze/FreezeFactory.sol";
import {StaticFeeCalculatorFactory} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculatorFactory.sol";
import {
    StaticAddressConditionFactory
} from "../src/plugins/conditions/access/static-address/StaticAddressConditionFactory.sol";
import {AndConditionFactory} from "../src/plugins/conditions/combinators/AndConditionFactory.sol";
import {OrConditionFactory} from "../src/plugins/conditions/combinators/OrConditionFactory.sol";
import {NotConditionFactory} from "../src/plugins/conditions/combinators/NotConditionFactory.sol";
import {RecorderCombinatorFactory} from "../src/plugins/recorders/combinators/RecorderCombinatorFactory.sol";

// Additional
import {RefundRequestFactory} from "../src/requests/refund/RefundRequestFactory.sol";
import {ReceiverRefundCollector} from "../src/collectors/ReceiverRefundCollector.sol";
import {RefundRequestEvidenceFactory} from "../src/evidence/RefundRequestEvidenceFactory.sol";

/**
 * @title DeployCreate3
 * @notice Deterministic deployment of all x402r contracts via CREATE3 (CreateX).
 *         Same deployer + same salt = same address on every EVM chain.
 *
 * @dev On the Shanghai profile, Solady's ReentrancyGuardTransient is remapped to an
 *      SSTORE-only drop-in so TSTORE/TLOAD/MCOPY never appear in the bytecode.
 *
 *      SALT is appended to each contract's base label to form the CREATE3 salt.
 *      Use SALT="" for first deployment, SALT="-v2" for redeployment at new addresses, etc.
 *      NOTE: Salt labels differ from v1/v2 deployments (e.g. "refund-request-factory" was
 *      "sig-refund-request-factory"). Always use a fresh SALT when migrating from old addresses.
 *
 *      Cancun+ chains (Base, Ethereum, Arbitrum, …):
 *        SALT="-v3" USDC_ADDRESS=0x... TVL_LIMIT=100000000000 \
 *        forge script script/DeployCreate3.s.sol --rpc-url <RPC> --broadcast --verify -vvvv
 *
 *      SKALE (Shanghai EVM):
 *        FOUNDRY_PROFILE=shanghai SALT="-v3" USDC_ADDRESS=0x... TVL_LIMIT=100000000000 \
 *        forge script script/DeployCreate3.s.sol --rpc-url skale-base --broadcast --legacy --slow -vvvv
 */
contract DeployCreate3 is Create3Deployer {
    address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        string memory salt = vm.envString("SALT");
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);
        address protocolFeeRecipient = vm.envOr("PROTOCOL_FEE_RECIPIENT", msg.sender);
        uint256 protocolFeeBps = vm.envOr("PROTOCOL_FEE_BPS", uint256(0));
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        uint256 tvlLimit = vm.envUint("TVL_LIMIT");

        console.log("\n========================================");
        console.log("  x402r CREATE3 Deployment");
        console.log("========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", vm.addr(deployerPk));
        console.log("Salt:", salt);
        console.log("Owner:", owner);
        console.log("Fee Recipient:", protocolFeeRecipient);
        console.log("Fee BPS:", protocolFeeBps);
        console.log("USDC:", usdcAddress);
        console.log("TVL Limit:", tvlLimit);

        vm.startBroadcast(deployerPk);

        // =============================================
        // 1. Core (commerce-payments)
        // =============================================
        console.log("\n--- 1. Core Contracts ---");

        address escrow = _deploy3("escrow", salt, type(AuthCaptureEscrow).creationCode);
        console.log("AuthCaptureEscrow:", escrow);

        address tokenCollector = _deploy3(
            "token-collector",
            salt,
            abi.encodePacked(type(ERC3009PaymentCollector).creationCode, abi.encode(escrow, MULTICALL3))
        );
        console.log("TokenCollector:", tokenCollector);

        // =============================================
        // 2. Protocol Infrastructure
        // =============================================
        console.log("\n--- 2. Protocol Infrastructure ---");

        address calculatorAddr = address(0);
        if (protocolFeeBps > 0) {
            calculatorAddr = _deploy3(
                "static-fee-calculator",
                salt,
                abi.encodePacked(type(StaticFeeCalculator).creationCode, abi.encode(protocolFeeBps))
            );
            console.log("StaticFeeCalculator:", calculatorAddr);
        }

        address protocolFeeConfig = _deploy3(
            "protocol-fee-config",
            salt,
            abi.encodePacked(
                type(ProtocolFeeConfig).creationCode, abi.encode(calculatorAddr, protocolFeeRecipient, owner)
            )
        );
        console.log("ProtocolFeeConfig:", protocolFeeConfig);

        address paymentOperatorFactory = _deploy3(
            "payment-operator-factory",
            salt,
            abi.encodePacked(type(PaymentOperatorFactory).creationCode, abi.encode(escrow, protocolFeeConfig))
        );
        console.log("PaymentOperatorFactory:", paymentOperatorFactory);

        // =============================================
        // 3. Singletons
        // =============================================
        console.log("\n--- 3. Singletons ---");

        address sigCondFactory = _deploy3("sig-condition-factory", salt, type(SignatureConditionFactory).creationCode);
        console.log("SignatureConditionFactory:", sigCondFactory);

        address arbiterRegistry = _deploy3("arbiter-registry", salt, type(ArbiterRegistry).creationCode);
        console.log("ArbiterRegistry:", arbiterRegistry);

        address refundReqFactory = _deploy3("refund-request-factory", salt, type(RefundRequestFactory).creationCode);
        console.log("RefundRequestFactory:", refundReqFactory);

        // =============================================
        // 4. Condition Singletons
        // =============================================
        console.log("\n--- 4. Condition Singletons ---");

        address payerCondition = _deploy3("payer-condition", salt, type(PayerCondition).creationCode);
        console.log("PayerCondition:", payerCondition);

        address receiverCondition = _deploy3("receiver-condition", salt, type(ReceiverCondition).creationCode);
        console.log("ReceiverCondition:", receiverCondition);

        address alwaysTrueCondition = _deploy3("always-true-condition", salt, type(AlwaysTrueCondition).creationCode);
        console.log("AlwaysTrueCondition:", alwaysTrueCondition);

        address usdcTvlLimit = _deploy3(
            "usdc-tvl-limit",
            salt,
            abi.encodePacked(type(UsdcTvlLimit).creationCode, abi.encode(escrow, usdcAddress, tvlLimit))
        );
        console.log("UsdcTvlLimit:", usdcTvlLimit);

        // =============================================
        // 5. Factories
        // =============================================
        console.log("\n--- 5. Factories ---");

        address escrowPeriodFactory = _deploy3(
            "escrow-period-factory", salt, abi.encodePacked(type(EscrowPeriodFactory).creationCode, abi.encode(escrow))
        );
        console.log("EscrowPeriodFactory:", escrowPeriodFactory);

        address freezeFactory =
            _deploy3("freeze-factory", salt, abi.encodePacked(type(FreezeFactory).creationCode, abi.encode(escrow)));
        console.log("FreezeFactory:", freezeFactory);

        address staticFeeCalcFactory =
            _deploy3("static-fee-calc-factory", salt, type(StaticFeeCalculatorFactory).creationCode);
        console.log("StaticFeeCalculatorFactory:", staticFeeCalcFactory);

        address staticAddrCondFactory =
            _deploy3("static-addr-condition-factory", salt, type(StaticAddressConditionFactory).creationCode);
        console.log("StaticAddressConditionFactory:", staticAddrCondFactory);

        address andFactory = _deploy3("and-condition-factory", salt, type(AndConditionFactory).creationCode);
        console.log("AndConditionFactory:", andFactory);

        address orFactory = _deploy3("or-condition-factory", salt, type(OrConditionFactory).creationCode);
        console.log("OrConditionFactory:", orFactory);

        address notFactory = _deploy3("not-condition-factory", salt, type(NotConditionFactory).creationCode);
        console.log("NotConditionFactory:", notFactory);

        address recorderCombFactory =
            _deploy3("recorder-combinator-factory", salt, type(RecorderCombinatorFactory).creationCode);
        console.log("RecorderCombinatorFactory:", recorderCombFactory);

        // =============================================
        // 6. Additional
        // =============================================
        console.log("\n--- 6. Additional ---");

        address receiverRefundCollector = _deploy3(
            "receiver-refund-collector",
            salt,
            abi.encodePacked(type(ReceiverRefundCollector).creationCode, abi.encode(escrow))
        );
        console.log("ReceiverRefundCollector:", receiverRefundCollector);

        address refundRequestEvidenceFactory =
            _deploy3("refund-request-evidence-factory", salt, type(RefundRequestEvidenceFactory).creationCode);
        console.log("RefundRequestEvidenceFactory:", refundRequestEvidenceFactory);

        vm.stopBroadcast();

        // =============================================
        // Summary
        // =============================================
        console.log("\n========================================");
        console.log("  DEPLOYMENT SUMMARY (CREATE3)");
        console.log("========================================");
        console.log("  Same address on all chains (sender-guarded):");
        console.log("    authCaptureEscrow:", escrow);
        console.log("    tokenCollector:", tokenCollector);
        console.log("    protocolFeeConfig:", protocolFeeConfig);
        console.log("    paymentOperatorFactory:", paymentOperatorFactory);
        console.log("    signatureConditionFactory:", sigCondFactory);
        console.log("    arbiterRegistry:", arbiterRegistry);
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
        console.log("    recorderCombinatorFactory:", recorderCombFactory);
        console.log("    receiverRefundCollector:", receiverRefundCollector);
        console.log("    refundRequestEvidenceFactory:", refundRequestEvidenceFactory);
        console.log("========================================");
    }
}
