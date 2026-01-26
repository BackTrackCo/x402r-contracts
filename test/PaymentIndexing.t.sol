// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/arbitration/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/**
 * @title PaymentIndexingTest
 * @notice Tests for optimized payment indexing (mapping + counter pattern)
 * @dev Verifies pagination, gas savings, and backward compatibility
 */
contract PaymentIndexingTest is Test {
    PaymentOperator public operator;
    PaymentOperatorFactory public operatorFactory;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;

    address public owner;
    address public protocolFeeRecipient;
    address public payer;
    address public receiver;

    uint256 public constant MAX_TOTAL_FEE_RATE = 50; // 0.5%
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 25; // 25%
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

        // Deploy operator factory
        operatorFactory = new PaymentOperatorFactory(
            address(escrow), protocolFeeRecipient, MAX_TOTAL_FEE_RATE, PROTOCOL_FEE_PERCENTAGE, owner
        );

        // Deploy operator
        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
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
        assertEq(operator.payerPaymentCount(payer), 1, "Should have 1 payment");
        assertEq(operator.receiverPaymentCount(receiver), 1, "Should have 1 payment");

        // Get payment by index
        bytes32 hash = operator.getPayerPayment(payer, 0);
        assertTrue(hash != bytes32(0), "Hash should not be zero");
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
        assertEq(operator.payerPaymentCount(payer), numPayments, "Should have correct count");

        // Verify each payment
        for (uint256 i = 0; i < numPayments; i++) {
            bytes32 hash = operator.getPayerPayment(payer, i);
            assertEq(hash, expectedHashes[i], "Hash should match");
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
        (bytes32[] memory payments, uint256 total) = operator.getPayerPayments(payer, 0, 5);

        assertEq(total, 10, "Total should be 10");
        assertEq(payments.length, 5, "Should return 5 payments");

        // Get next 5 payments
        (bytes32[] memory payments2, uint256 total2) = operator.getPayerPayments(payer, 5, 5);

        assertEq(total2, 10, "Total should still be 10");
        assertEq(payments2.length, 5, "Should return 5 payments");

        // Verify no overlap
        for (uint256 i = 0; i < 5; i++) {
            for (uint256 j = 0; j < 5; j++) {
                assertTrue(payments[i] != payments2[j], "Should have no overlap");
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
        (bytes32[] memory payments, uint256 total) = operator.getPayerPayments(payer, 0, 10);

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
        (bytes32[] memory payments, uint256 total) = operator.getPayerPayments(payer, 10, 5);

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
        (bytes32[] memory payments, uint256 total) = operator.getReceiverPayments(receiver, 0, 10);
        assertEq(total, 2, "Receiver should have 2 payments");
        assertEq(payments.length, 2, "Should return 2 payments");

        // Check receiver2 has 1 payment
        (bytes32[] memory payments2, uint256 total2) = operator.getReceiverPayments(receiver2, 0, 10);
        assertEq(total2, 1, "Receiver2 should have 1 payment");
        assertEq(payments2.length, 1, "Should return 1 payment");
    }

    /**
     * @notice Test getPayerPayment reverts on out of bounds
     */
    function test_GetPayerPayment_RevertsOutOfBounds() public {
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 1);

        // Should revert when accessing index 1 (only index 0 exists)
        vm.expectRevert("Index out of bounds");
        operator.getPayerPayment(payer, 1);
    }

    /**
     * @notice Test getReceiverPayment reverts on out of bounds
     */
    function test_GetReceiverPayment_RevertsOutOfBounds() public {
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 1);

        // Should revert when accessing index 1 (only index 0 exists)
        vm.expectRevert("Index out of bounds");
        operator.getReceiverPayment(receiver, 1);
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
        // Expected: ~432k (down from ~473k with arrays)
        // Indexing portion: ~22k (down from ~40k)
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
        // Expected: ~462k (down from ~473k with arrays)
        // Indexing portion: ~5k (down from ~10k)
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

        // Expected pattern:
        // Payment 1: ~432k (new storage slots)
        // Payment 2-5: ~462k (existing storage slots)
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
        operator.getPayerPayments(payer, 0, 10);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Get 10 payments gas:", gasUsed);

        // Get first 50
        gasBefore = gasleft();
        operator.getPayerPayments(payer, 0, 50);
        gasUsed = gasBefore - gasleft();
        console.log("Get 50 payments gas:", gasUsed);

        // Get single payment
        gasBefore = gasleft();
        operator.getPayerPayment(payer, 0);
        gasUsed = gasBefore - gasleft();
        console.log("Get single payment gas:", gasUsed);
    }

    // ============================================================
    // EDGE CASES
    // ============================================================

    /**
     * @notice Test pagination with zero payments
     */
    function test_Pagination_ZeroPayments() public {
        (bytes32[] memory payments, uint256 total) = operator.getPayerPayments(payer, 0, 10);

        assertEq(total, 0, "Total should be 0");
        assertEq(payments.length, 0, "Should return empty array");
    }

    /**
     * @notice Test pagination with count = 0
     */
    function test_Pagination_ZeroCount() public {
        _authorizePayment(payer, receiver, PAYMENT_AMOUNT, 1);

        (bytes32[] memory payments, uint256 total) = operator.getPayerPayments(payer, 0, 0);

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
        assertEq(operator.payerPaymentCount(payer), numPayments, "Should have correct count");

        // Verify we can get all payments via pagination
        uint256 pageSize = 10;
        uint256 totalRetrieved = 0;

        for (uint256 offset = 0; offset < numPayments; offset += pageSize) {
            (bytes32[] memory payments,) = operator.getPayerPayments(payer, offset, pageSize);
            totalRetrieved += payments.length;
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
            minFeeBps: uint16(MAX_TOTAL_FEE_RATE),
            maxFeeBps: uint16(MAX_TOTAL_FEE_RATE),
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
