// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {PaymentOperator} from "../../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {ReceiverRefundCollector} from "../../src/collectors/ReceiverRefundCollector.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ProtocolFeeConfig} from "../../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../../src/plugins/fees/static-fee-calculator/StaticFeeCalculator.sol";
import {EscrowPeriod} from "../../src/plugins/escrow-period/EscrowPeriod.sol";
import {EscrowPeriodFactory} from "../../src/plugins/escrow-period/EscrowPeriodFactory.sol";
import {Freeze} from "../../src/plugins/freeze/Freeze.sol";
import {ICondition} from "../../src/plugins/conditions/ICondition.sol";
import {AndCondition} from "../../src/plugins/conditions/combinators/AndCondition.sol";
import {PayerCondition} from "../../src/plugins/conditions/access/PayerCondition.sol";
import {ReceiverCondition} from "../../src/plugins/conditions/access/ReceiverCondition.sol";

import {RefundRequest} from "../../src/requests/refund/RefundRequest.sol";
import {RefundRequestEvidence} from "../../src/evidence/RefundRequestEvidence.sol";

/**
 * @title GasBenchmark
 * @notice Gas measurements for documentation. Compares:
 *         1. Bare ERC-20 transfer
 *         2. Commerce Payments (no conditions/recorders)
 *         3. x402r happy path (EscrowPeriod + Freeze conditions)
 *         4. x402r unhappy path (freeze, refund request, evidence, refund)
 *
 *         Run: forge test --match-contract GasBenchmark -vv
 */
contract GasBenchmark is Test {
    // ============ Infrastructure ============
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    ReceiverRefundCollector public refundCollector;
    MockERC20 public token;

    // ============ Fee System ============
    ProtocolFeeConfig public protocolFeeConfig;
    StaticFeeCalculator public protocolCalc;
    StaticFeeCalculator public operatorCalc;

    // ============ Plugins ============
    EscrowPeriod public escrowPeriod;
    Freeze public freeze;
    AndCondition public captureCondition;
    PayerCondition public payerCondition;

    // ============ Operators ============
    PaymentOperatorFactory public operatorFactory;
    PaymentOperatorFactory public bareOperatorFactory; // No protocol fees
    PaymentOperator public bareOperator; // No conditions/recorders/fees
    PaymentOperator public feesOnlyOperator; // Fees, no conditions/recorders
    PaymentOperator public simpleOperator; // Fees + ReceiverCondition on release
    PaymentOperator public escrowOnlyOperator; // Fees + EscrowPeriod (no Freeze)
    PaymentOperator public fullOperator; // EscrowPeriod + Freeze + fees

    // ============ Dispute System ============
    RefundRequest public refundRequest;
    RefundRequestEvidence public refundRequestEvidence;

    // ============ Accounts ============
    address public owner;
    address public protocolFeeRecipient;
    address public operatorFeeRecipient;
    address public payer;
    address public receiver;
    address public arbiter;

    // ============ Constants ============
    uint256 public constant PROTOCOL_BPS = 25;
    uint256 public constant OPERATOR_BPS = 50;
    uint256 public constant TOTAL_BPS = PROTOCOL_BPS + OPERATOR_BPS;
    uint256 public constant ESCROW_PERIOD_DURATION = 7 days;
    uint256 public constant FREEZE_DURATION = 3 days;
    uint256 public constant PAYMENT_AMOUNT = 100 * 10 ** 6; // 100 USDC (6 decimals)

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        operatorFeeRecipient = makeAddr("operatorFeeRecipient");
        payer = makeAddr("payer");
        receiver = makeAddr("receiver");

        arbiter = makeAddr("arbiter");

        // Deploy infrastructure
        escrow = new AuthCaptureEscrow();
        token = new MockERC20("USDC", "USDC");
        collector = new PreApprovalPaymentCollector(address(escrow));
        refundCollector = new ReceiverRefundCollector(address(escrow));

        // Deploy fee calculators
        protocolCalc = new StaticFeeCalculator(PROTOCOL_BPS);
        operatorCalc = new StaticFeeCalculator(OPERATOR_BPS);
        protocolFeeConfig = new ProtocolFeeConfig(address(protocolCalc), protocolFeeRecipient, owner);

        // Deploy escrow period
        EscrowPeriodFactory escrowPeriodFactory = new EscrowPeriodFactory(address(escrow));
        payerCondition = new PayerCondition();
        address escrowPeriodAddr = escrowPeriodFactory.deploy(ESCROW_PERIOD_DURATION, bytes32(0));
        escrowPeriod = EscrowPeriod(escrowPeriodAddr);

        // Deploy freeze
        freeze = new Freeze(
            address(payerCondition), address(payerCondition), FREEZE_DURATION, address(escrowPeriod), address(escrow)
        );

        // Compose release condition: EscrowPeriod AND NOT Frozen
        ICondition[] memory conditions = new ICondition[](2);
        conditions[0] = ICondition(address(escrowPeriod));
        conditions[1] = ICondition(address(freeze));
        captureCondition = new AndCondition(conditions);

        // Deploy operator factories
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        // Bare factory: no protocol fee
        ProtocolFeeConfig bareProtocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        bareOperatorFactory = new PaymentOperatorFactory(address(escrow), address(bareProtocolFeeConfig));

        // --- BARE OPERATOR (no conditions, no recorders, no fees) ---
        PaymentOperatorFactory.OperatorConfig memory bareConfig = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: operatorFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            captureCondition: address(0),
            captureRecorder: address(0),
            voidCondition: address(0),
            voidRecorder: address(0),
            refundCondition: address(0),
            refundRecorder: address(0)
        });
        bareOperator = PaymentOperator(bareOperatorFactory.deployOperator(bareConfig));

        // --- FEES-ONLY OPERATOR (fees, no conditions/recorders) ---
        PaymentOperatorFactory.OperatorConfig memory feesOnlyConfig = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: operatorFeeRecipient,
            feeCalculator: address(operatorCalc),
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            captureCondition: address(0),
            captureRecorder: address(0),
            voidCondition: address(0),
            voidRecorder: address(0),
            refundCondition: address(0),
            refundRecorder: address(0)
        });
        feesOnlyOperator = PaymentOperator(operatorFactory.deployOperator(feesOnlyConfig));

        // --- SIMPLE OPERATOR (fees + ReceiverCondition on release) ---
        ReceiverCondition receiverCondition = new ReceiverCondition();
        PaymentOperatorFactory.OperatorConfig memory simpleConfig = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: operatorFeeRecipient,
            feeCalculator: address(operatorCalc),
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            captureCondition: address(receiverCondition),
            captureRecorder: address(0),
            voidCondition: address(0),
            voidRecorder: address(0),
            refundCondition: address(0),
            refundRecorder: address(0)
        });
        simpleOperator = PaymentOperator(operatorFactory.deployOperator(simpleConfig));

        // --- ESCROW-ONLY OPERATOR (fees + EscrowPeriod recorder + EscrowPeriod release condition, no Freeze) ---
        PaymentOperatorFactory.OperatorConfig memory escrowOnlyConfig = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: operatorFeeRecipient,
            feeCalculator: address(operatorCalc),
            authorizeCondition: address(0),
            authorizeRecorder: address(escrowPeriod),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            captureCondition: address(escrowPeriod),
            captureRecorder: address(0),
            voidCondition: address(0),
            voidRecorder: address(0),
            refundCondition: address(0),
            refundRecorder: address(0)
        });
        escrowOnlyOperator = PaymentOperator(operatorFactory.deployOperator(escrowOnlyConfig));

        // --- FULL OPERATOR (EscrowPeriod recorder, EscrowPeriod+Freeze release condition, fees) ---
        PaymentOperatorFactory.OperatorConfig memory fullConfig = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: operatorFeeRecipient,
            feeCalculator: address(operatorCalc),
            authorizeCondition: address(0),
            authorizeRecorder: address(escrowPeriod),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            captureCondition: address(captureCondition),
            captureRecorder: address(0),
            voidCondition: address(0),
            voidRecorder: address(0),
            refundCondition: address(0),
            refundRecorder: address(0)
        });
        fullOperator = PaymentOperator(operatorFactory.deployOperator(fullConfig));

        // Deploy dispute system
        refundRequest = new RefundRequest(arbiter);
        refundRequestEvidence = new RefundRequestEvidence(address(refundRequest));

        // Fund accounts
        token.mint(payer, PAYMENT_AMOUNT * 100);
        token.mint(receiver, PAYMENT_AMOUNT * 100);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
        vm.prank(receiver);
        token.approve(address(collector), type(uint256).max);
        vm.prank(receiver);
        token.approve(address(refundCollector), type(uint256).max);
    }

    // ================================================================
    //  1. BASELINE: ERC-20 TRANSFER
    // ================================================================

    function test_gas_erc20Transfer() public {
        // Warm the storage slots first (not first-ever transfer)
        vm.prank(payer);
        token.transfer(receiver, 1);

        vm.prank(payer);
        uint256 gasBefore = gasleft();
        token.transfer(receiver, PAYMENT_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== BASELINE ===");
        console.log("ERC-20 transfer:", gasUsed);
    }

    function test_gas_erc20TransferCold() public {
        // First-ever transfer (cold storage)
        address freshPayer = makeAddr("freshPayer");
        token.mint(freshPayer, PAYMENT_AMOUNT * 10);

        vm.prank(freshPayer);
        uint256 gasBefore = gasleft();
        token.transfer(receiver, PAYMENT_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== BASELINE ===");
        console.log("ERC-20 transfer (cold):", gasUsed);
    }

    // ================================================================
    //  2. BARE COMMERCE PAYMENTS (no conditions, no recorders, no fees)
    // ================================================================

    function test_gas_bareAuthorize() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(bareOperator), 0, 1);

        vm.prank(payer);
        collector.preApprove(pi);

        uint256 gasBefore = gasleft();
        bareOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== BARE COMMERCE PAYMENTS ===");
        console.log("authorize (no conditions/recorders):", gasUsed);
    }

    function test_gas_bareRelease() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(bareOperator), 0, 2);

        vm.prank(payer);
        collector.preApprove(pi);
        bareOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(receiver);
        uint256 gasBefore = gasleft();
        bareOperator.capture(pi, PAYMENT_AMOUNT, "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== BARE COMMERCE PAYMENTS ===");
        console.log("release (no conditions/recorders):", gasUsed);
    }

    function test_gas_bareCharge() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(bareOperator), 0, 3);

        vm.prank(payer);
        collector.preApprove(pi);

        uint256 gasBefore = gasleft();
        bareOperator.charge(pi, PAYMENT_AMOUNT, address(collector), "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== BARE COMMERCE PAYMENTS ===");
        console.log("charge (no conditions/recorders):", gasUsed);
    }

    // ================================================================
    //  2b. FEES ONLY (no conditions, no recorders)
    // ================================================================

    function test_gas_feesOnlyAuthorize() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(feesOnlyOperator), TOTAL_BPS, 4);

        vm.prank(payer);
        collector.preApprove(pi);

        uint256 gasBefore = gasleft();
        feesOnlyOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== FEES ONLY ===");
        console.log("authorize (fees, no conditions/recorders):", gasUsed);
    }

    function test_gas_feesOnlyRelease() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(feesOnlyOperator), TOTAL_BPS, 5);

        vm.prank(payer);
        collector.preApprove(pi);
        feesOnlyOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(receiver);
        uint256 gasBefore = gasleft();
        feesOnlyOperator.capture(pi, PAYMENT_AMOUNT, "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== FEES ONLY ===");
        console.log("release (fees, no conditions/recorders):", gasUsed);
    }

    // ================================================================
    //  2c. SIMPLE CONDITIONS (fees + ReceiverCondition on release)
    // ================================================================

    function test_gas_simpleAuthorize() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(simpleOperator), TOTAL_BPS, 6);

        vm.prank(payer);
        collector.preApprove(pi);

        uint256 gasBefore = gasleft();
        simpleOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== SIMPLE CONDITIONS ===");
        console.log("authorize (fees, no auth condition/recorder):", gasUsed);
    }

    function test_gas_simpleRelease() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(simpleOperator), TOTAL_BPS, 7);

        vm.prank(payer);
        collector.preApprove(pi);
        simpleOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(receiver);
        uint256 gasBefore = gasleft();
        simpleOperator.capture(pi, PAYMENT_AMOUNT, "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== SIMPLE CONDITIONS ===");
        console.log("release (fees + ReceiverCondition):", gasUsed);
    }

    // ================================================================
    //  3. x402r FULL (EscrowPeriod + Freeze + Fees)
    // ================================================================

    function test_gas_x402rAuthorizeColdVsWarm() public {
        // Cold: first authorize on this operator in a transaction.
        // Contract addresses (fee calculator, protocol fee config, escrow, escrow period)
        // are accessed for the first time — each cold CALL costs 2,600 gas.
        AuthCaptureEscrow.PaymentInfo memory pi1 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 8);
        vm.prank(payer);
        collector.preApprove(pi1);
        uint256 g1 = gasleft();
        fullOperator.authorize(pi1, PAYMENT_AMOUNT, address(collector), "");
        uint256 coldGas = g1 - gasleft();

        // Warm: second authorize on same operator in the same transaction.
        // All contract addresses and code are already in the EVM access list.
        // The per-payment storage (escrow hash, authorizedFees) is still new,
        // but shared infrastructure reads are warm.
        AuthCaptureEscrow.PaymentInfo memory pi2 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 9);
        vm.prank(payer);
        collector.preApprove(pi2);
        uint256 g2 = gasleft();
        fullOperator.authorize(pi2, PAYMENT_AMOUNT, address(collector), "");
        uint256 warmGas = g2 - gasleft();

        console.log("=== AUTHORIZE COLD vs WARM ===");
        console.log("cold (first authorize on operator):", coldGas);
        console.log("warm (second authorize, contracts cached):", warmGas);
        console.log("savings:", coldGas - warmGas);

        // Also measure bare operator cold vs warm
        AuthCaptureEscrow.PaymentInfo memory piBare1 = _createPaymentInfo(address(bareOperator), 0, 80);
        vm.prank(payer);
        collector.preApprove(piBare1);
        uint256 g3 = gasleft();
        bareOperator.authorize(piBare1, PAYMENT_AMOUNT, address(collector), "");
        uint256 bareColdGas = g3 - gasleft();

        AuthCaptureEscrow.PaymentInfo memory piBare2 = _createPaymentInfo(address(bareOperator), 0, 81);
        vm.prank(payer);
        collector.preApprove(piBare2);
        uint256 g4 = gasleft();
        bareOperator.authorize(piBare2, PAYMENT_AMOUNT, address(collector), "");
        uint256 bareWarmGas = g4 - gasleft();

        console.log("bare cold:", bareColdGas);
        console.log("bare warm:", bareWarmGas);
        console.log("bare savings:", bareColdGas - bareWarmGas);
    }

    function test_gas_x402rAuthorize() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 10);

        vm.prank(payer);
        collector.preApprove(pi);

        uint256 gasBefore = gasleft();
        fullOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== x402r HAPPY PATH ===");
        console.log("authorize (EscrowPeriod recorder + fees):", gasUsed);
    }

    function test_gas_x402rRelease() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 11);

        vm.prank(payer);
        collector.preApprove(pi);
        fullOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        // Warp past escrow period
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);

        vm.prank(receiver);
        uint256 gasBefore = gasleft();
        fullOperator.capture(pi, PAYMENT_AMOUNT, "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== x402r HAPPY PATH ===");
        console.log("release (EscrowPeriod + Freeze conditions + fees):", gasUsed);
    }

    function test_gas_x402rDistributeFees() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 12);

        vm.prank(payer);
        collector.preApprove(pi);
        fullOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);
        vm.prank(receiver);
        fullOperator.capture(pi, PAYMENT_AMOUNT, "");

        uint256 gasBefore = gasleft();
        fullOperator.distributeFees(address(token));
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== x402r HAPPY PATH ===");
        console.log("distributeFees:", gasUsed);
    }

    // ================================================================
    //  4. x402r UNHAPPY PATH (dispute, refund)
    // ================================================================

    function test_gas_freeze() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 20);

        vm.prank(payer);
        collector.preApprove(pi);
        fullOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        uint256 gasBefore = gasleft();
        freeze.freeze(pi, "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== x402r UNHAPPY PATH ===");
        console.log("freeze:", gasUsed);
    }

    function test_gas_requestRefund() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 21);

        vm.prank(payer);
        collector.preApprove(pi);
        fullOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        uint256 gasBefore = gasleft();
        refundRequest.requestRefund(pi, uint120(PAYMENT_AMOUNT));
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== x402r UNHAPPY PATH ===");
        console.log("requestRefund:", gasUsed);
    }

    function test_gas_approveRefund() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 22);

        vm.prank(payer);
        collector.preApprove(pi);
        fullOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        refundRequest.requestRefund(pi, uint120(PAYMENT_AMOUNT));

        vm.prank(arbiter);
        uint256 gasBefore = gasleft();
        fullOperator.void(pi, "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== x402r UNHAPPY PATH ===");
        console.log("approve:", gasUsed);
    }

    function test_gas_submitEvidence() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 23);

        vm.prank(payer);
        collector.preApprove(pi);
        fullOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        refundRequest.requestRefund(pi, uint120(PAYMENT_AMOUNT));

        vm.prank(payer);
        uint256 gasBefore = gasleft();
        refundRequestEvidence.submitEvidence(pi, "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== x402r UNHAPPY PATH ===");
        console.log("submitEvidence:", gasUsed);
    }

    function test_gas_void() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 24);

        vm.prank(payer);
        collector.preApprove(pi);
        fullOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        uint256 gasBefore = gasleft();
        fullOperator.void(pi, "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== x402r UNHAPPY PATH ===");
        console.log("void:", gasUsed);
    }

    function test_gas_refundPostEscrow() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 25);

        vm.prank(payer);
        collector.preApprove(pi);
        fullOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");

        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);
        vm.prank(receiver);
        fullOperator.capture(pi, PAYMENT_AMOUNT, "");

        // Receiver already approved refundCollector in setUp()
        uint256 netAmount = PAYMENT_AMOUNT - (PAYMENT_AMOUNT * TOTAL_BPS) / 10000;

        uint256 gasBefore = gasleft();
        fullOperator.refund(pi, netAmount, address(refundCollector), "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("=== x402r UNHAPPY PATH ===");
        console.log("refundPostEscrow:", gasUsed);
    }

    // ================================================================
    //  4b. COLD vs WARM: RELEASE
    // ================================================================

    function test_gas_x402rReleaseColdVsWarm() public {
        // Authorize two payments on the full operator
        AuthCaptureEscrow.PaymentInfo memory pi1 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 60);
        AuthCaptureEscrow.PaymentInfo memory pi2 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 61);

        vm.prank(payer);
        collector.preApprove(pi1);
        fullOperator.authorize(pi1, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        collector.preApprove(pi2);
        fullOperator.authorize(pi2, PAYMENT_AMOUNT, address(collector), "");

        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);

        // Cold release: first release in this transaction
        vm.prank(receiver);
        uint256 g1 = gasleft();
        fullOperator.capture(pi1, PAYMENT_AMOUNT, "");
        uint256 coldGas = g1 - gasleft();

        // Warm release: second release, contracts cached
        vm.prank(receiver);
        uint256 g2 = gasleft();
        fullOperator.capture(pi2, PAYMENT_AMOUNT, "");
        uint256 warmGas = g2 - gasleft();

        console.log("=== RELEASE COLD vs WARM ===");
        console.log("cold:", coldGas);
        console.log("warm:", warmGas);
        console.log("savings:", coldGas - warmGas);
    }

    // ================================================================
    //  4c. COLD vs WARM: DISTRIBUTE FEES
    // ================================================================

    function test_gas_x402rDistributeFeesColdVsWarm() public {
        // Create two payments on two separate operators so we can distribute fees twice
        AuthCaptureEscrow.PaymentInfo memory pi1 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 62);
        vm.prank(payer);
        collector.preApprove(pi1);
        fullOperator.authorize(pi1, PAYMENT_AMOUNT, address(collector), "");

        AuthCaptureEscrow.PaymentInfo memory pi2 = _createPaymentInfo(address(escrowOnlyOperator), TOTAL_BPS, 63);
        vm.prank(payer);
        collector.preApprove(pi2);
        escrowOnlyOperator.authorize(pi2, PAYMENT_AMOUNT, address(collector), "");

        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);

        vm.prank(receiver);
        fullOperator.capture(pi1, PAYMENT_AMOUNT, "");
        vm.prank(receiver);
        escrowOnlyOperator.capture(pi2, PAYMENT_AMOUNT, "");

        // Cold distributeFees
        uint256 g1 = gasleft();
        fullOperator.distributeFees(address(token));
        uint256 coldGas = g1 - gasleft();

        // Warm distributeFees (different operator, but token/recipient contracts already warm)
        uint256 g2 = gasleft();
        escrowOnlyOperator.distributeFees(address(token));
        uint256 warmGas = g2 - gasleft();

        console.log("=== DISTRIBUTE FEES COLD vs WARM ===");
        console.log("cold:", coldGas);
        console.log("warm:", warmGas);
        console.log("savings:", coldGas - warmGas);
    }

    // ================================================================
    //  4d. COLD vs WARM: DISPUTE OPERATIONS
    // ================================================================

    function test_gas_freezeColdVsWarm() public {
        AuthCaptureEscrow.PaymentInfo memory pi1 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 64);
        AuthCaptureEscrow.PaymentInfo memory pi2 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 65);

        vm.prank(payer);
        collector.preApprove(pi1);
        fullOperator.authorize(pi1, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        collector.preApprove(pi2);
        fullOperator.authorize(pi2, PAYMENT_AMOUNT, address(collector), "");

        // Cold freeze
        vm.prank(payer);
        uint256 g1 = gasleft();
        freeze.freeze(pi1, "");
        uint256 coldGas = g1 - gasleft();

        // Warm freeze
        vm.prank(payer);
        uint256 g2 = gasleft();
        freeze.freeze(pi2, "");
        uint256 warmGas = g2 - gasleft();

        console.log("=== FREEZE COLD vs WARM ===");
        console.log("cold:", coldGas);
        console.log("warm:", warmGas);
        console.log("savings:", coldGas - warmGas);
    }

    function test_gas_requestRefundColdVsWarm() public {
        AuthCaptureEscrow.PaymentInfo memory pi1 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 66);
        AuthCaptureEscrow.PaymentInfo memory pi2 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 67);

        vm.prank(payer);
        collector.preApprove(pi1);
        fullOperator.authorize(pi1, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        collector.preApprove(pi2);
        fullOperator.authorize(pi2, PAYMENT_AMOUNT, address(collector), "");

        // Cold requestRefund
        vm.prank(payer);
        uint256 g1 = gasleft();
        refundRequest.requestRefund(pi1, uint120(PAYMENT_AMOUNT));
        uint256 coldGas = g1 - gasleft();

        // Warm requestRefund
        vm.prank(payer);
        uint256 g2 = gasleft();
        refundRequest.requestRefund(pi2, uint120(PAYMENT_AMOUNT));
        uint256 warmGas = g2 - gasleft();

        console.log("=== REQUEST REFUND COLD vs WARM ===");
        console.log("cold:", coldGas);
        console.log("warm:", warmGas);
        console.log("savings:", coldGas - warmGas);
    }

    function test_gas_submitEvidenceColdVsWarm() public {
        AuthCaptureEscrow.PaymentInfo memory pi1 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 68);
        AuthCaptureEscrow.PaymentInfo memory pi2 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 69);

        vm.prank(payer);
        collector.preApprove(pi1);
        fullOperator.authorize(pi1, PAYMENT_AMOUNT, address(collector), "");
        vm.prank(payer);
        refundRequest.requestRefund(pi1, uint120(PAYMENT_AMOUNT));

        vm.prank(payer);
        collector.preApprove(pi2);
        fullOperator.authorize(pi2, PAYMENT_AMOUNT, address(collector), "");
        vm.prank(payer);
        refundRequest.requestRefund(pi2, uint120(PAYMENT_AMOUNT));

        // Cold submitEvidence
        vm.prank(payer);
        uint256 g1 = gasleft();
        refundRequestEvidence.submitEvidence(pi1, "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG");
        uint256 coldGas = g1 - gasleft();

        // Warm submitEvidence
        vm.prank(payer);
        uint256 g2 = gasleft();
        refundRequestEvidence.submitEvidence(pi2, "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG");
        uint256 warmGas = g2 - gasleft();

        console.log("=== SUBMIT EVIDENCE COLD vs WARM ===");
        console.log("cold:", coldGas);
        console.log("warm:", warmGas);
        console.log("savings:", coldGas - warmGas);
    }

    function test_gas_approveRefundColdVsWarm() public {
        AuthCaptureEscrow.PaymentInfo memory pi1 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 70);
        AuthCaptureEscrow.PaymentInfo memory pi2 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 71);

        vm.prank(payer);
        collector.preApprove(pi1);
        fullOperator.authorize(pi1, PAYMENT_AMOUNT, address(collector), "");
        vm.prank(payer);
        refundRequest.requestRefund(pi1, uint120(PAYMENT_AMOUNT));

        vm.prank(payer);
        collector.preApprove(pi2);
        fullOperator.authorize(pi2, PAYMENT_AMOUNT, address(collector), "");
        vm.prank(payer);
        refundRequest.requestRefund(pi2, uint120(PAYMENT_AMOUNT));

        // Cold approve
        vm.prank(arbiter);
        uint256 g1 = gasleft();
        fullOperator.void(pi1, "");
        uint256 coldGas = g1 - gasleft();

        // Warm approve
        vm.prank(arbiter);
        uint256 g2 = gasleft();
        fullOperator.void(pi2, "");
        uint256 warmGas = g2 - gasleft();

        console.log("=== APPROVE REFUND COLD vs WARM ===");
        console.log("cold:", coldGas);
        console.log("warm:", warmGas);
        console.log("savings:", coldGas - warmGas);
    }

    function test_gas_voidColdVsWarm() public {
        AuthCaptureEscrow.PaymentInfo memory pi1 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 72);
        AuthCaptureEscrow.PaymentInfo memory pi2 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 73);

        vm.prank(payer);
        collector.preApprove(pi1);
        fullOperator.authorize(pi1, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        collector.preApprove(pi2);
        fullOperator.authorize(pi2, PAYMENT_AMOUNT, address(collector), "");

        // Cold void
        uint256 g1 = gasleft();
        fullOperator.void(pi1, "");
        uint256 coldGas = g1 - gasleft();

        // Warm void
        uint256 g2 = gasleft();
        fullOperator.void(pi2, "");
        uint256 warmGas = g2 - gasleft();

        console.log("=== REFUND IN ESCROW COLD vs WARM ===");
        console.log("cold:", coldGas);
        console.log("warm:", warmGas);
        console.log("savings:", coldGas - warmGas);
    }

    function test_gas_refundPostEscrowColdVsWarm() public {
        AuthCaptureEscrow.PaymentInfo memory pi1 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 74);
        AuthCaptureEscrow.PaymentInfo memory pi2 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 75);

        vm.prank(payer);
        collector.preApprove(pi1);
        fullOperator.authorize(pi1, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        collector.preApprove(pi2);
        fullOperator.authorize(pi2, PAYMENT_AMOUNT, address(collector), "");

        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);

        vm.prank(receiver);
        fullOperator.capture(pi1, PAYMENT_AMOUNT, "");
        vm.prank(receiver);
        fullOperator.capture(pi2, PAYMENT_AMOUNT, "");

        uint256 netAmount = PAYMENT_AMOUNT - (PAYMENT_AMOUNT * TOTAL_BPS) / 10000;

        // Cold refundPostEscrow
        uint256 g1 = gasleft();
        fullOperator.refund(pi1, netAmount, address(refundCollector), "");
        uint256 coldGas = g1 - gasleft();

        // Warm refundPostEscrow
        uint256 g2 = gasleft();
        fullOperator.refund(pi2, netAmount, address(refundCollector), "");
        uint256 warmGas = g2 - gasleft();

        console.log("=== REFUND POST ESCROW COLD vs WARM ===");
        console.log("cold:", coldGas);
        console.log("warm:", warmGas);
        console.log("savings:", coldGas - warmGas);
    }

    // ================================================================
    //  4e. COLD vs WARM: OVERHEAD COMPARISON (authorize + release tiers)
    // ================================================================

    function test_gas_overhead_authorize_coldVsWarm() public {
        // --- COLD PASS (first call to each operator) ---
        AuthCaptureEscrow.PaymentInfo memory piBare1 = _createPaymentInfo(address(bareOperator), 0, 90);
        vm.prank(payer);
        collector.preApprove(piBare1);
        uint256 g1 = gasleft();
        bareOperator.authorize(piBare1, PAYMENT_AMOUNT, address(collector), "");
        uint256 bareCold = g1 - gasleft();

        AuthCaptureEscrow.PaymentInfo memory piFees1 = _createPaymentInfo(address(feesOnlyOperator), TOTAL_BPS, 91);
        vm.prank(payer);
        collector.preApprove(piFees1);
        uint256 g2 = gasleft();
        feesOnlyOperator.authorize(piFees1, PAYMENT_AMOUNT, address(collector), "");
        uint256 feesCold = g2 - gasleft();

        AuthCaptureEscrow.PaymentInfo memory piEscrow1 = _createPaymentInfo(address(escrowOnlyOperator), TOTAL_BPS, 92);
        vm.prank(payer);
        collector.preApprove(piEscrow1);
        uint256 g3 = gasleft();
        escrowOnlyOperator.authorize(piEscrow1, PAYMENT_AMOUNT, address(collector), "");
        uint256 escrowCold = g3 - gasleft();

        AuthCaptureEscrow.PaymentInfo memory piFull1 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 93);
        vm.prank(payer);
        collector.preApprove(piFull1);
        uint256 g4 = gasleft();
        fullOperator.authorize(piFull1, PAYMENT_AMOUNT, address(collector), "");
        uint256 fullCold = g4 - gasleft();

        // --- WARM PASS (second call to each operator, contracts cached) ---
        AuthCaptureEscrow.PaymentInfo memory piBare2 = _createPaymentInfo(address(bareOperator), 0, 94);
        vm.prank(payer);
        collector.preApprove(piBare2);
        uint256 g5 = gasleft();
        bareOperator.authorize(piBare2, PAYMENT_AMOUNT, address(collector), "");
        uint256 bareWarm = g5 - gasleft();

        AuthCaptureEscrow.PaymentInfo memory piFees2 = _createPaymentInfo(address(feesOnlyOperator), TOTAL_BPS, 95);
        vm.prank(payer);
        collector.preApprove(piFees2);
        uint256 g6 = gasleft();
        feesOnlyOperator.authorize(piFees2, PAYMENT_AMOUNT, address(collector), "");
        uint256 feesWarm = g6 - gasleft();

        AuthCaptureEscrow.PaymentInfo memory piEscrow2 = _createPaymentInfo(address(escrowOnlyOperator), TOTAL_BPS, 96);
        vm.prank(payer);
        collector.preApprove(piEscrow2);
        uint256 g7 = gasleft();
        escrowOnlyOperator.authorize(piEscrow2, PAYMENT_AMOUNT, address(collector), "");
        uint256 escrowWarm = g7 - gasleft();

        AuthCaptureEscrow.PaymentInfo memory piFull2 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 97);
        vm.prank(payer);
        collector.preApprove(piFull2);
        uint256 g8 = gasleft();
        fullOperator.authorize(piFull2, PAYMENT_AMOUNT, address(collector), "");
        uint256 fullWarm = g8 - gasleft();

        console.log("=== AUTHORIZE OVERHEAD COLD vs WARM ===");
        console.log("bare cold:", bareCold);
        console.log("bare warm:", bareWarm);
        console.log("fees cold:", feesCold);
        console.log("fees warm:", feesWarm);
        console.log("escrow cold:", escrowCold);
        console.log("escrow warm:", escrowWarm);
        console.log("full cold:", fullCold);
        console.log("full warm:", fullWarm);
    }

    function test_gas_overhead_release_coldVsWarm() public {
        // Authorize ALL operators (two payments each) before warping
        AuthCaptureEscrow.PaymentInfo memory piBare1 = _createPaymentInfo(address(bareOperator), 0, 100);
        AuthCaptureEscrow.PaymentInfo memory piBare2 = _createPaymentInfo(address(bareOperator), 0, 101);
        AuthCaptureEscrow.PaymentInfo memory piFees1 = _createPaymentInfo(address(feesOnlyOperator), TOTAL_BPS, 102);
        AuthCaptureEscrow.PaymentInfo memory piFees2 = _createPaymentInfo(address(feesOnlyOperator), TOTAL_BPS, 103);
        AuthCaptureEscrow.PaymentInfo memory piSimple1 = _createPaymentInfo(address(simpleOperator), TOTAL_BPS, 104);
        AuthCaptureEscrow.PaymentInfo memory piSimple2 = _createPaymentInfo(address(simpleOperator), TOTAL_BPS, 105);
        AuthCaptureEscrow.PaymentInfo memory piEscrow1 = _createPaymentInfo(address(escrowOnlyOperator), TOTAL_BPS, 106);
        AuthCaptureEscrow.PaymentInfo memory piEscrow2 = _createPaymentInfo(address(escrowOnlyOperator), TOTAL_BPS, 107);
        AuthCaptureEscrow.PaymentInfo memory piFull1 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 108);
        AuthCaptureEscrow.PaymentInfo memory piFull2 = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 109);

        vm.prank(payer);
        collector.preApprove(piBare1);
        bareOperator.authorize(piBare1, PAYMENT_AMOUNT, address(collector), "");
        vm.prank(payer);
        collector.preApprove(piBare2);
        bareOperator.authorize(piBare2, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        collector.preApprove(piFees1);
        feesOnlyOperator.authorize(piFees1, PAYMENT_AMOUNT, address(collector), "");
        vm.prank(payer);
        collector.preApprove(piFees2);
        feesOnlyOperator.authorize(piFees2, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        collector.preApprove(piSimple1);
        simpleOperator.authorize(piSimple1, PAYMENT_AMOUNT, address(collector), "");
        vm.prank(payer);
        collector.preApprove(piSimple2);
        simpleOperator.authorize(piSimple2, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        collector.preApprove(piEscrow1);
        escrowOnlyOperator.authorize(piEscrow1, PAYMENT_AMOUNT, address(collector), "");
        vm.prank(payer);
        collector.preApprove(piEscrow2);
        escrowOnlyOperator.authorize(piEscrow2, PAYMENT_AMOUNT, address(collector), "");

        vm.prank(payer);
        collector.preApprove(piFull1);
        fullOperator.authorize(piFull1, PAYMENT_AMOUNT, address(collector), "");
        vm.prank(payer);
        collector.preApprove(piFull2);
        fullOperator.authorize(piFull2, PAYMENT_AMOUNT, address(collector), "");

        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);

        // --- COLD PASS ---
        vm.prank(receiver);
        uint256 g1 = gasleft();
        bareOperator.capture(piBare1, PAYMENT_AMOUNT, "");
        uint256 bareCold = g1 - gasleft();

        vm.prank(receiver);
        uint256 g2 = gasleft();
        feesOnlyOperator.capture(piFees1, PAYMENT_AMOUNT, "");
        uint256 feesCold = g2 - gasleft();

        vm.prank(receiver);
        uint256 g3 = gasleft();
        simpleOperator.capture(piSimple1, PAYMENT_AMOUNT, "");
        uint256 simpleCold = g3 - gasleft();

        vm.prank(receiver);
        uint256 g4 = gasleft();
        escrowOnlyOperator.capture(piEscrow1, PAYMENT_AMOUNT, "");
        uint256 escrowCold = g4 - gasleft();

        vm.prank(receiver);
        uint256 g5 = gasleft();
        fullOperator.capture(piFull1, PAYMENT_AMOUNT, "");
        uint256 fullCold = g5 - gasleft();

        // --- WARM PASS ---
        vm.prank(receiver);
        uint256 g6 = gasleft();
        bareOperator.capture(piBare2, PAYMENT_AMOUNT, "");
        uint256 bareWarm = g6 - gasleft();

        vm.prank(receiver);
        uint256 g7 = gasleft();
        feesOnlyOperator.capture(piFees2, PAYMENT_AMOUNT, "");
        uint256 feesWarm = g7 - gasleft();

        vm.prank(receiver);
        uint256 g8 = gasleft();
        simpleOperator.capture(piSimple2, PAYMENT_AMOUNT, "");
        uint256 simpleWarm = g8 - gasleft();

        vm.prank(receiver);
        uint256 g9 = gasleft();
        escrowOnlyOperator.capture(piEscrow2, PAYMENT_AMOUNT, "");
        uint256 escrowWarm = g9 - gasleft();

        vm.prank(receiver);
        uint256 g10 = gasleft();
        fullOperator.capture(piFull2, PAYMENT_AMOUNT, "");
        uint256 fullWarm = g10 - gasleft();

        console.log("=== RELEASE OVERHEAD COLD vs WARM ===");
        console.log("bare cold:", bareCold);
        console.log("bare warm:", bareWarm);
        console.log("fees cold:", feesCold);
        console.log("fees warm:", feesWarm);
        console.log("simple cold:", simpleCold);
        console.log("simple warm:", simpleWarm);
        console.log("escrow cold:", escrowCold);
        console.log("escrow warm:", escrowWarm);
        console.log("full cold:", fullCold);
        console.log("full warm:", fullWarm);
    }

    // ================================================================
    //  5. CONDITION/RECORDER OVERHEAD COMPARISON
    // ================================================================

    function test_gas_overhead_authorize() public {
        // Bare
        AuthCaptureEscrow.PaymentInfo memory piBare = _createPaymentInfo(address(bareOperator), 0, 30);
        vm.prank(payer);
        collector.preApprove(piBare);
        uint256 g1 = gasleft();
        bareOperator.authorize(piBare, PAYMENT_AMOUNT, address(collector), "");
        uint256 bareGas = g1 - gasleft();

        // Fees only (no conditions, no recorders)
        AuthCaptureEscrow.PaymentInfo memory piFees = _createPaymentInfo(address(feesOnlyOperator), TOTAL_BPS, 31);
        vm.prank(payer);
        collector.preApprove(piFees);
        uint256 g2 = gasleft();
        feesOnlyOperator.authorize(piFees, PAYMENT_AMOUNT, address(collector), "");
        uint256 feesGas = g2 - gasleft();

        // Escrow-only (fees + EscrowPeriod recorder)
        AuthCaptureEscrow.PaymentInfo memory piEscrow = _createPaymentInfo(address(escrowOnlyOperator), TOTAL_BPS, 32);
        vm.prank(payer);
        collector.preApprove(piEscrow);
        uint256 g3 = gasleft();
        escrowOnlyOperator.authorize(piEscrow, PAYMENT_AMOUNT, address(collector), "");
        uint256 escrowGas = g3 - gasleft();

        // Full (fees + EscrowPeriod recorder — same as escrow-only for authorize)
        AuthCaptureEscrow.PaymentInfo memory piFull = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 33);
        vm.prank(payer);
        collector.preApprove(piFull);
        uint256 g4 = gasleft();
        fullOperator.authorize(piFull, PAYMENT_AMOUNT, address(collector), "");
        uint256 fullGas = g4 - gasleft();

        console.log("=== AUTHORIZE OVERHEAD ===");
        console.log("bare (no fees/conditions/recorders):", bareGas);
        console.log("+ fees:", feesGas);
        console.log("+ fees + EscrowPeriod recorder:", escrowGas);
        console.log("+ fees + EscrowPeriod recorder (full):", fullGas);
        console.log("--- marginal costs ---");
        console.log("fee calculation:", feesGas - bareGas);
        console.log("EscrowPeriod recorder:", escrowGas - feesGas);
    }

    function test_gas_overhead_release() public {
        // Authorize ALL operators first, then warp, then release.
        // This avoids preApprovalExpiry issues from warping mid-test.

        // Bare
        AuthCaptureEscrow.PaymentInfo memory piBare = _createPaymentInfo(address(bareOperator), 0, 34);
        vm.prank(payer);
        collector.preApprove(piBare);
        bareOperator.authorize(piBare, PAYMENT_AMOUNT, address(collector), "");

        // Fees only
        AuthCaptureEscrow.PaymentInfo memory piFees = _createPaymentInfo(address(feesOnlyOperator), TOTAL_BPS, 35);
        vm.prank(payer);
        collector.preApprove(piFees);
        feesOnlyOperator.authorize(piFees, PAYMENT_AMOUNT, address(collector), "");

        // Simple (fees + ReceiverCondition)
        AuthCaptureEscrow.PaymentInfo memory piSimple = _createPaymentInfo(address(simpleOperator), TOTAL_BPS, 36);
        vm.prank(payer);
        collector.preApprove(piSimple);
        simpleOperator.authorize(piSimple, PAYMENT_AMOUNT, address(collector), "");

        // Escrow-only (fees + EscrowPeriod condition, no Freeze)
        AuthCaptureEscrow.PaymentInfo memory piEscrow = _createPaymentInfo(address(escrowOnlyOperator), TOTAL_BPS, 37);
        vm.prank(payer);
        collector.preApprove(piEscrow);
        escrowOnlyOperator.authorize(piEscrow, PAYMENT_AMOUNT, address(collector), "");

        // Full (EscrowPeriod + Freeze via AndCondition + fees)
        AuthCaptureEscrow.PaymentInfo memory piFull = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 38);
        vm.prank(payer);
        collector.preApprove(piFull);
        fullOperator.authorize(piFull, PAYMENT_AMOUNT, address(collector), "");

        // Warp past escrow period (needed for escrow-only and full operators)
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);

        // Release: bare
        vm.prank(receiver);
        uint256 g1 = gasleft();
        bareOperator.capture(piBare, PAYMENT_AMOUNT, "");
        uint256 bareGas = g1 - gasleft();

        // Release: fees only
        vm.prank(receiver);
        uint256 g2 = gasleft();
        feesOnlyOperator.capture(piFees, PAYMENT_AMOUNT, "");
        uint256 feesGas = g2 - gasleft();

        // Release: simple
        vm.prank(receiver);
        uint256 g3 = gasleft();
        simpleOperator.capture(piSimple, PAYMENT_AMOUNT, "");
        uint256 simpleGas = g3 - gasleft();

        // Release: escrow-only
        vm.prank(receiver);
        uint256 g4 = gasleft();
        escrowOnlyOperator.capture(piEscrow, PAYMENT_AMOUNT, "");
        uint256 escrowGas = g4 - gasleft();

        // Release: full
        vm.prank(receiver);
        uint256 g5 = gasleft();
        fullOperator.capture(piFull, PAYMENT_AMOUNT, "");
        uint256 fullGas = g5 - gasleft();

        console.log("=== RELEASE OVERHEAD ===");
        console.log("bare (no fees/conditions):", bareGas);
        console.log("+ fees:", feesGas);
        console.log("+ fees + ReceiverCondition:", simpleGas);
        console.log("+ fees + EscrowPeriod:", escrowGas);
        console.log("+ fees + EscrowPeriod + Freeze (AndCondition):", fullGas);
        console.log("--- marginal costs ---");
        console.log("fee retrieval + distribution:", feesGas - bareGas);
        console.log("ReceiverCondition (pure calldata):", simpleGas - feesGas);
        console.log("EscrowPeriod (cross-contract storage):", escrowGas - feesGas);
        console.log("Freeze + AndCondition combinator:", fullGas - escrowGas);
    }

    // ================================================================
    //  6. FULL LIFECYCLE TOTALS
    // ================================================================

    function test_gas_fullHappyPath() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 40);

        // preApprove (client off-chain equivalent)
        vm.prank(payer);
        collector.preApprove(pi);

        // authorize
        uint256 g1 = gasleft();
        fullOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");
        uint256 authorizeGas = g1 - gasleft();

        // warp + release
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);
        vm.prank(receiver);
        uint256 g2 = gasleft();
        fullOperator.capture(pi, PAYMENT_AMOUNT, "");
        uint256 releaseGas = g2 - gasleft();

        // distributeFees
        uint256 g3 = gasleft();
        fullOperator.distributeFees(address(token));
        uint256 feeGas = g3 - gasleft();

        uint256 total = authorizeGas + releaseGas + feeGas;

        console.log("=== FULL HAPPY PATH TOTAL ===");
        console.log("authorize:", authorizeGas);
        console.log("release:", releaseGas);
        console.log("distributeFees:", feeGas);
        console.log("TOTAL:", total);
    }

    function test_gas_fullUnhappyPath() public {
        AuthCaptureEscrow.PaymentInfo memory pi = _createPaymentInfo(address(fullOperator), TOTAL_BPS, 50);

        // authorize
        vm.prank(payer);
        collector.preApprove(pi);
        uint256 g1 = gasleft();
        fullOperator.authorize(pi, PAYMENT_AMOUNT, address(collector), "");
        uint256 authorizeGas = g1 - gasleft();

        // freeze
        vm.prank(payer);
        uint256 g2 = gasleft();
        freeze.freeze(pi, "");
        uint256 freezeGas = g2 - gasleft();

        // warp past freeze + escrow, release
        vm.warp(block.timestamp + ESCROW_PERIOD_DURATION + 1);
        vm.prank(receiver);
        uint256 g3 = gasleft();
        fullOperator.capture(pi, PAYMENT_AMOUNT, "");
        uint256 releaseGas = g3 - gasleft();

        // requestRefund
        vm.prank(payer);
        uint256 g4 = gasleft();
        refundRequest.requestRefund(pi, uint120(PAYMENT_AMOUNT));
        uint256 requestGas = g4 - gasleft();

        // submitEvidence (payer)
        vm.prank(payer);
        uint256 g5 = gasleft();
        refundRequestEvidence.submitEvidence(pi, "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG");
        uint256 evidenceGas = g5 - gasleft();

        // approve (arbiter approves — but this is post-escrow, so approve won't work with void)
        // In v2, approve() atomically calls void, which only works while in escrow.
        // For post-escrow flow, the refund request is just tracked (no atomic execution).
        // Measure deny instead (same state machine cost).
        vm.prank(arbiter);
        uint256 g6 = gasleft();
        refundRequest.deny(pi);
        uint256 denyGas = g6 - gasleft();

        // refundPostEscrow
        uint256 netAmount = PAYMENT_AMOUNT - (PAYMENT_AMOUNT * TOTAL_BPS) / 10000;
        uint256 g7 = gasleft();
        fullOperator.refund(pi, netAmount, address(refundCollector), "");
        uint256 refundGas = g7 - gasleft();

        uint256 total = authorizeGas + freezeGas + releaseGas + requestGas + evidenceGas + denyGas + refundGas;

        console.log("=== FULL UNHAPPY PATH TOTAL ===");
        console.log("authorize:", authorizeGas);
        console.log("freeze:", freezeGas);
        console.log("release:", releaseGas);
        console.log("requestRefund:", requestGas);
        console.log("submitEvidence:", evidenceGas);
        console.log("deny:", denyGas);
        console.log("refundPostEscrow:", refundGas);
        console.log("TOTAL:", total);
    }

    // ================================================================
    //  HELPERS
    // ================================================================

    function _createPaymentInfo(address op, uint256 feeBps, uint256 salt)
        internal
        view
        returns (AuthCaptureEscrow.PaymentInfo memory)
    {
        return AuthCaptureEscrow.PaymentInfo({
            operator: op,
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 30 days),
            refundExpiry: uint48(block.timestamp + 60 days),
            minFeeBps: uint16(feeBps),
            maxFeeBps: uint16(feeBps),
            feeReceiver: op,
            salt: salt
        });
    }
}
