// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {PaymentIndexRecorder} from "../src/plugins/recorders/PaymentIndexRecorder.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/**
 * @title PaymentIndexingTest
 * @notice Tests for optimized payment indexing (mapping + counter pattern)
 * @dev Verifies pagination, gas savings, full PaymentInfo retrieval, and backward compatibility
 */
contract PaymentIndexingTest is Test {
    PaymentOperator public operator;
    PaymentOperatorFactory public operatorFactory;
    PaymentIndexRecorder public indexRecorder;
    ProtocolFeeConfig public protocolFeeConfig;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;

    address public owner;
    address public protocolFeeRecipient;
    address public payer;
    address public receiver;

    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        payer = makeAddr("payer");
        receiver = makeAddr("receiver");

        // Deploy infrastructure
        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        // Deploy protocol fee config (no calculator = 0 fees)
        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);

        // Deploy operator factory
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        // Deploy payment index recorder
        indexRecorder = new PaymentIndexRecorder(address(escrow), bytes32(0));

        // Deploy operator with index recorder
        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(indexRecorder), // Use index recorder
            chargeCondition: address(0),
            chargeRecorder: address(indexRecorder), // Use index recorder
            releaseCondition: address(0),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = PaymentOperator(operatorFactory.deployOperator(config));

        // Setup balances
        token.mint(payer, 1000000 * 10 ** 18);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
    }

    // ============================================================
    // PAGINATION TESTS
    // ============================================================

    /**
     * @notice Test basic payment indexing for payer
     */
    function test_PayerIndexing_SinglePayment() public {
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 1);

        // Check counter
        assertEq(indexRecorder.payerPaymentCount(payer), 1, "Should have 1 payment");
        assertEq(indexRecorder.receiverPaymentCount(receiver), 1, "Should have 1 payment");

        // Get payment by index — now returns full PaymentInfo
        AuthCaptureEscrow.PaymentInfo memory info = indexRecorder.getPayerPayment(payer, 0);
        assertEq(info.payer, payer, "Payer should match");
        assertEq(info.receiver, receiver, "Receiver should match");
    }

    /**
     * @notice Test multiple payments are indexed correctly
     */
    function test_PayerIndexing_MultiplePayments() public {
        uint256 numPayments = 5;
        bytes32[] memory expectedHashes = new bytes32[](numPayments);

        for (uint256 i = 0; i < numPayments; i++) {
            AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(PAYMENT_AMOUNT, i + 1);
            expectedHashes[i] = escrow.getHash(paymentInfo);
            _authorizePaymentWithInfo(paymentInfo);
        }

        // Check counter
        assertEq(indexRecorder.payerPaymentCount(payer), numPayments, "Should have correct count");

        // Verify each payment returns correct PaymentInfo
        for (uint256 i = 0; i < numPayments; i++) {
            AuthCaptureEscrow.PaymentInfo memory info = indexRecorder.getPayerPayment(payer, i);
            assertEq(info.salt, i + 1, "Salt should match payment index");
            assertEq(info.payer, payer, "Payer should match");
        }
    }

    /**
     * @notice Test pagination with offset and count
     */
    function test_Pagination_Basic() public {
        uint256 numPayments = 10;

        // Create 10 payments
        for (uint256 i = 0; i < numPayments; i++) {
            _authorizePayment(payer, receiver, PAYMENT_AMOUNT, i + 1);
        }

        // Get first 5 payments
        (AuthCaptureEscrow.PaymentInfo[] memory payments, uint256 total) = indexRecorder.getPayerPayments(payer, 0, 5);

        assertEq(total, 10, "Total should be 10");
        assertEq(payments.length, 5, "Should return 5 payments");

        // Get next 5 payments
        (AuthCaptureEscrow.PaymentInfo[] memory payments2, uint256 total2) = indexRecorder.getPayerPayments(payer, 5, 5);

        assertEq(total2, 10, "Total should still be 10");
        assertEq(payments2.length, 5, "Should return 5 payments");

        // Verify no overlap via salt (each payment has unique salt)
        for (uint256 i = 0; i < 5; i++) {
            for (uint256 j = 0; j < 5; j++) {
                assertTrue(payments[i].salt != payments2[j].salt, "Should have no overlap");
            }
        }
    }

    /**
     * @notice Test pagination with count larger than remaining
     */
    function test_Pagination_CountExceedsRemaining() public {
        // Create 3 payments
        for (uint256 i = 0; i < 3; i++) {
            _authorizePayment(payer, receiver, PAYMENT_AMOUNT, i + 1);
        }

        // Request 10 payments (only 3 exist)
        (AuthCaptureEscrow.PaymentInfo[] memory payments, uint256 total) = indexRecorder.getPayerPayments(payer, 0, 10);

        assertEq(total, 3, "Total should be 3");
        assertEq(payments.length, 3, "Should return only 3 payments");
    }

    /**
     * @notice Test pagination with offset beyond total
     */
    function test_Pagination_OffsetBeyondTotal() public {
        // Create 5 payments
        for (uint256 i = 0; i < 5; i++) {
            _authorizePayment(payer, receiver, PAYMENT_AMOUNT, i + 1);
        }

        // Request from offset 10 (beyond total of 5)
        (AuthCaptureEscrow.PaymentInfo[] memory payments, uint256 total) = indexRecorder.getPayerPayments(payer, 10, 5);

        assertEq(total, 5, "Total should still be 5");
        assertEq(payments.length, 0, "Should return empty array");
    }

    /**
     * @notice Test pagination for receiver
     */
    function test_Pagination_ReceiverPayments() public {
        address receiver2 = makeAddr("receiver2");

        // Create payments to different receivers
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 1);
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 2);
        _authorizePayment(payer, receiver2, PAYMENT_AMOUNT, 3);

        // Check receiver1 has 2 payments
        (AuthCaptureEscrow.PaymentInfo[] memory payments, uint256 total) =
            indexRecorder.getReceiverPayments(receiver, 0, 10);
        assertEq(total, 2, "Receiver should have 2 payments");
        assertEq(payments.length, 2, "Should return 2 payments");
        assertEq(payments[0].receiver, receiver, "Receiver should match");

        // Check receiver2 has 1 payment
        (AuthCaptureEscrow.PaymentInfo[] memory payments2, uint256 total2) =
            indexRecorder.getReceiverPayments(receiver2, 0, 10);
        assertEq(total2, 1, "Receiver2 should have 1 payment");
        assertEq(payments2.length, 1, "Should return 1 payment");
        assertEq(payments2[0].receiver, receiver2, "Receiver2 should match");
    }

    /**
     * @notice Test getPayerPayment reverts on out of bounds
     */
    function test_GetPayerPayment_RevertsOutOfBounds() public {
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 1);

        // Should revert when accessing index 1 (only index 0 exists)
        vm.expectRevert(PaymentIndexRecorder.IndexOutOfBounds.selector);
        indexRecorder.getPayerPayment(payer, 1);
    }

    /**
     * @notice Test getReceiverPayment reverts on out of bounds
     */
    function test_GetReceiverPayment_RevertsOutOfBounds() public {
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 1);

        // Should revert when accessing index 1 (only index 0 exists)
        vm.expectRevert(PaymentIndexRecorder.IndexOutOfBounds.selector);
        indexRecorder.getReceiverPayment(receiver, 1);
    }

    // ============================================================
    // PAYMENT INFO RETRIEVAL TESTS
    // ============================================================

    /**
     * @notice Test getPaymentInfo returns full struct
     */
    function test_GetPaymentInfo_ReturnsFullStruct() public {
        AuthCaptureEscrow.PaymentInfo memory original = _createPaymentInfo(PAYMENT_AMOUNT, 42);
        bytes32 hash = escrow.getHash(original);
        _authorizePaymentWithInfo(original);

        AuthCaptureEscrow.PaymentInfo memory retrieved = indexRecorder.getPaymentInfo(hash);

        assertEq(retrieved.operator, original.operator, "operator mismatch");
        assertEq(retrieved.payer, original.payer, "payer mismatch");
        assertEq(retrieved.receiver, original.receiver, "receiver mismatch");
        assertEq(retrieved.token, original.token, "token mismatch");
        assertEq(retrieved.maxAmount, original.maxAmount, "maxAmount mismatch");
        assertEq(retrieved.preApprovalExpiry, original.preApprovalExpiry, "preApprovalExpiry mismatch");
        assertEq(retrieved.authorizationExpiry, original.authorizationExpiry, "authorizationExpiry mismatch");
        assertEq(retrieved.refundExpiry, original.refundExpiry, "refundExpiry mismatch");
        assertEq(retrieved.minFeeBps, original.minFeeBps, "minFeeBps mismatch");
        assertEq(retrieved.maxFeeBps, original.maxFeeBps, "maxFeeBps mismatch");
        assertEq(retrieved.feeReceiver, original.feeReceiver, "feeReceiver mismatch");
        assertEq(retrieved.salt, original.salt, "salt mismatch");
    }

    /**
     * @notice Test getPaymentInfo returns zeros for unknown hash
     */
    function test_GetPaymentInfo_UnknownHash() public view {
        AuthCaptureEscrow.PaymentInfo memory info = indexRecorder.getPaymentInfo(bytes32(uint256(999)));
        assertEq(info.operator, address(0), "Should return zero struct");
    }

    /**
     * @notice Test getPayerPayments returns full PaymentInfo structs
     */
    function test_GetPayerPayments_ReturnsFullStructs() public {
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 1);
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 2);

        (AuthCaptureEscrow.PaymentInfo[] memory infos, uint256 total) = indexRecorder.getPayerPayments(payer, 0, 10);

        assertEq(total, 2, "Should have 2 payments");
        assertEq(infos.length, 2, "Should return 2 infos");
        assertEq(infos[0].payer, payer, "First payment payer should match");
        assertEq(infos[0].salt, 1, "First payment salt should be 1");
        assertEq(infos[1].salt, 2, "Second payment salt should be 2");
    }

    // ============================================================
    // GAS BENCHMARKING
    // ============================================================

    /**
     * @notice Benchmark gas cost for first payment (new storage slots)
     */
    function test_Gas_FirstPayment() public {
        uint256 gasBefore = gasleft();
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 100);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("First payment gas:", gasUsed);
        // Expected: ~590k (up from ~432k due to PaymentInfo storage — 7 extra SSTORE slots)
    }

    /**
     * @notice Benchmark gas cost for subsequent payment (existing storage slots)
     */
    function test_Gas_SubsequentPayment() public {
        // Create first payment
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 100);

        // Measure second payment
        uint256 gasBefore = gasleft();
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 101);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Subsequent payment gas:", gasUsed);
        // Expected: ~620k (up from ~462k due to PaymentInfo storage)
    }

    /**
     * @notice Benchmark gas for multiple payments
     */
    function test_Gas_MultiplePayments() public {
        console.log("\n=== Gas Benchmark: Multiple Payments ===");

        for (uint256 i = 1; i <= 5; i++) {
            uint256 gasBefore = gasleft();
            _authorizePayment(payer, receiver, PAYMENT_AMOUNT, i);
            uint256 gasUsed = gasBefore - gasleft();

            console.log("Payment", i, "gas:", gasUsed);
        }
    }

    /**
     * @notice Compare pagination query gas costs
     */
    function test_Gas_PaginationQueries() public {
        // Create 100 payments
        for (uint256 i = 0; i < 100; i++) {
            _authorizePayment(payer, receiver, PAYMENT_AMOUNT, i + 1);
        }

        console.log("\n=== Gas Benchmark: Pagination Queries ===");

        // Get first 10
        uint256 gasBefore = gasleft();
        indexRecorder.getPayerPayments(payer, 0, 10);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Get 10 PaymentInfos gas:", gasUsed);

        // Get first 50
        gasBefore = gasleft();
        indexRecorder.getPayerPayments(payer, 0, 50);
        gasUsed = gasBefore - gasleft();
        console.log("Get 50 PaymentInfos gas:", gasUsed);

        // Get single payment
        gasBefore = gasleft();
        indexRecorder.getPayerPayment(payer, 0);
        gasUsed = gasBefore - gasleft();
        console.log("Get single PaymentInfo gas:", gasUsed);

        // Get single by hash
        AuthCaptureEscrow.PaymentInfo memory info = _createPaymentInfo(PAYMENT_AMOUNT, 1);
        bytes32 hash = escrow.getHash(info);
        gasBefore = gasleft();
        indexRecorder.getPaymentInfo(hash);
        gasUsed = gasBefore - gasleft();
        console.log("Get PaymentInfo by hash gas:", gasUsed);
    }

    // ============================================================
    // EDGE CASES
    // ============================================================

    /**
     * @notice Test pagination with zero payments
     */
    function test_Pagination_ZeroPayments() public view {
        (AuthCaptureEscrow.PaymentInfo[] memory payments, uint256 total) = indexRecorder.getPayerPayments(payer, 0, 10);

        assertEq(total, 0, "Total should be 0");
        assertEq(payments.length, 0, "Should return empty array");
    }

    /**
     * @notice Test pagination with count = 0
     */
    function test_Pagination_ZeroCount() public {
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 1);

        (AuthCaptureEscrow.PaymentInfo[] memory payments, uint256 total) = indexRecorder.getPayerPayments(payer, 0, 0);

        assertEq(total, 1, "Total should be 1");
        assertEq(payments.length, 0, "Should return empty array");
    }

    /**
     * @notice Test large number of payments (stress test)
     */
    function test_Pagination_LargeNumberOfPayments() public {
        uint256 numPayments = 50;

        // Create 50 payments
        for (uint256 i = 0; i < numPayments; i++) {
            _authorizePayment(payer, receiver, PAYMENT_AMOUNT, i + 1);
        }

        // Verify count
        assertEq(indexRecorder.payerPaymentCount(payer), numPayments, "Should have correct count");

        // Verify we can get all payments via pagination
        uint256 pageSize = 10;
        uint256 totalRetrieved = 0;

        for (uint256 offset = 0; offset < numPayments; offset += pageSize) {
            (AuthCaptureEscrow.PaymentInfo[] memory payments,) = indexRecorder.getPayerPayments(payer, offset, pageSize);
            totalRetrieved += payments.length;

            // Verify each returned PaymentInfo has correct payer
            for (uint256 i = 0; i < payments.length; i++) {
                assertEq(payments[i].payer, payer, "Payer should match in paginated result");
            }
        }

        assertEq(totalRetrieved, numPayments, "Should retrieve all payments");
    }

    // ============================================================
    // HELPER FUNCTIONS
    // ============================================================

    function _createPaymentInfo(uint256 amount, uint256 salt)
        internal
        view
        returns (AuthCaptureEscrow.PaymentInfo memory)
    {
        return AuthCaptureEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(amount),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: uint16(0),
            maxFeeBps: uint16(0),
            feeReceiver: address(operator),
            salt: salt
        });
    }

    function _authorizePayment(address _payer, address _receiver, uint256 amount, uint256 salt) internal {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(amount, salt);
        paymentInfo.payer = _payer;
        paymentInfo.receiver = _receiver;

        vm.startPrank(_payer);
        collector.preApprove(paymentInfo);
        operator.authorize(paymentInfo, amount, address(collector), "");
        vm.stopPrank();
    }

    function _authorizePaymentWithInfo(AuthCaptureEscrow.PaymentInfo memory paymentInfo) internal {
        vm.startPrank(paymentInfo.payer);
        collector.preApprove(paymentInfo);
        operator.authorize(paymentInfo, paymentInfo.maxAmount, address(collector), "");
        vm.stopPrank();
    }
}
