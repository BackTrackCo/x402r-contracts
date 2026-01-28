// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {BaseRecorder} from "./BaseRecorder.sol";
import {ZeroAmount} from "../types/Errors.sol";

/**
 * @title PaymentIndexRecorder
 * @notice Recorder that indexes payments by payer and receiver for on-chain lookups
 * @dev Extracted from PaymentOperator for optional gas optimization.
 *      Deploy this recorder when you want on-chain payment queries.
 *      Skip (use address(0)) when using external indexer (The Graph).
 *
 * PATTERN: Mapping + counter for gas-efficient indexing
 *          - First write: 44k gas (2 storage slots: hash + amount)
 *          - Subsequent: 10k gas (update existing)
 *          - Stores: payment hash, amount
 *          - For timestamp: use EscrowPeriodRecorder (avoids duplication)
 *
 * GAS COST: ~20k per authorization (both payer + receiver indexing)
 *
 * USAGE:
 *   // Deploy once, share across operators
 *   PaymentIndexRecorder indexRecorder = new PaymentIndexRecorder(address(escrow));
 *
 *   // Query payments with amount context
 *   (PaymentRecord[] memory records, uint256 total) = indexRecorder.getPayerPayments(alice, 0, 10);
 *   // records[0].paymentHash, records[0].amount
 */
contract PaymentIndexRecorder is BaseRecorder {
    // ============ Errors ============
    error AmountExceedsMax();
    error IndexOutOfBounds();

    /// @notice Payment record with hash, amount, and record index
    struct PaymentRecord {
        bytes32 paymentHash; // 32 bytes (slot 1)
        uint120 amount; // 15 bytes (slot 2)
        uint128 recordIndex; // 16 bytes (slot 2) — total 31 bytes, fits in one slot
    }

    /// @notice Payer address => index => payment record
    mapping(address => mapping(uint256 => PaymentRecord)) private payerPayments;

    /// @notice Payer address => total payment count
    mapping(address => uint256) public payerPaymentCount;

    /// @notice Receiver address => index => payment record
    mapping(address => mapping(uint256 => PaymentRecord)) private receiverPayments;

    /// @notice Receiver address => total payment count
    mapping(address => uint256) public receiverPaymentCount;

    /// @notice Per-payment record count (how many times record() was called for a paymentInfoHash)
    mapping(bytes32 => uint256) public recordCount;

    /// @notice Emitted when a payment is indexed
    event PaymentIndexed(
        bytes32 indexed paymentHash,
        address indexed payer,
        address indexed receiver,
        uint120 amount,
        uint256 payerIndex,
        uint256 receiverIndex,
        uint256 recordIndex
    );

    constructor(address escrow, bytes32 authorizedCodehash) BaseRecorder(escrow, authorizedCodehash) {}

    /**
     * @notice Records payment by indexing it for both payer and receiver
     * @param paymentInfo Payment information to index
     * @param amount Amount authorized/charged
     * @param caller Address that executed the action (unused)
     */
    function record(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount, address caller)
        external
        override
    {
        bytes32 hash = _verifyAndHash(paymentInfo);

        // Validate amount
        if (amount == 0) revert ZeroAmount();
        if (amount > paymentInfo.maxAmount) revert AmountExceedsMax();

        // Track per-payment record index
        uint256 currentRecordIndex = recordCount[hash];
        recordCount[hash]++;

        // Create payment record
        PaymentRecord memory paymentRecord =
            PaymentRecord({paymentHash: hash, amount: uint120(amount), recordIndex: uint128(currentRecordIndex)});

        // Index for payer
        uint256 payerIndex = payerPaymentCount[paymentInfo.payer];
        payerPayments[paymentInfo.payer][payerIndex] = paymentRecord;
        payerPaymentCount[paymentInfo.payer]++;

        // Index for receiver
        uint256 receiverIndex = receiverPaymentCount[paymentInfo.receiver];
        receiverPayments[paymentInfo.receiver][receiverIndex] = paymentRecord;
        receiverPaymentCount[paymentInfo.receiver]++;

        emit PaymentIndexed(
            hash,
            paymentInfo.payer,
            paymentInfo.receiver,
            uint120(amount),
            payerIndex,
            receiverIndex,
            currentRecordIndex
        );
    }

    /**
     * @notice Get paginated list of payments for a payer
     * @param payer Address of the payer
     * @param offset Starting index (0-based)
     * @param count Number of payments to return
     * @return records Array of payment records (hash, amount)
     * @return total Total number of payments for this payer
     */
    function getPayerPayments(address payer, uint256 offset, uint256 count)
        external
        view
        returns (PaymentRecord[] memory records, uint256 total)
    {
        total = payerPaymentCount[payer];

        // Handle edge cases
        if (offset >= total || count == 0) {
            return (new PaymentRecord[](0), total);
        }

        // Calculate actual count to return
        uint256 remaining = total - offset;
        uint256 actualCount = remaining < count ? remaining : count;

        // Fill array
        records = new PaymentRecord[](actualCount);
        for (uint256 i = 0; i < actualCount; i++) {
            records[i] = payerPayments[payer][offset + i];
        }

        return (records, total);
    }

    /**
     * @notice Get a single payment record by index for a payer
     * @param payer Address of the payer
     * @param index Index of the payment (0-based)
     * @return Payment record at the specified index
     */
    function getPayerPayment(address payer, uint256 index) external view returns (PaymentRecord memory) {
        if (index >= payerPaymentCount[payer]) revert IndexOutOfBounds();
        return payerPayments[payer][index];
    }

    /**
     * @notice Get paginated list of payments for a receiver
     * @param receiver Address of the receiver
     * @param offset Starting index (0-based)
     * @param count Number of payments to return
     * @return records Array of payment records (hash, amount)
     * @return total Total number of payments for this receiver
     */
    function getReceiverPayments(address receiver, uint256 offset, uint256 count)
        external
        view
        returns (PaymentRecord[] memory records, uint256 total)
    {
        total = receiverPaymentCount[receiver];

        // Handle edge cases
        if (offset >= total || count == 0) {
            return (new PaymentRecord[](0), total);
        }

        // Calculate actual count to return
        uint256 remaining = total - offset;
        uint256 actualCount = remaining < count ? remaining : count;

        // Fill array
        records = new PaymentRecord[](actualCount);
        for (uint256 i = 0; i < actualCount; i++) {
            records[i] = receiverPayments[receiver][offset + i];
        }

        return (records, total);
    }

    /**
     * @notice Get a single payment record by index for a receiver
     * @param receiver Address of the receiver
     * @param index Index of the payment (0-based)
     * @return Payment record at the specified index
     */
    function getReceiverPayment(address receiver, uint256 index) external view returns (PaymentRecord memory) {
        if (index >= receiverPaymentCount[receiver]) revert IndexOutOfBounds();
        return receiverPayments[receiver][index];
    }
}
