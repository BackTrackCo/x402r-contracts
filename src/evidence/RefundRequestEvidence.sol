// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PaymentOperator} from "../operator/payment/PaymentOperator.sol";
import {RefundRequest} from "../requests/refund/RefundRequest.sol";
import {RefundRequestEvidenceAccess} from "./RefundRequestEvidenceAccess.sol";
import {SubmitterRole} from "./types/Types.sol";
import {EmptyCid, RefundRequestRequired} from "./types/Errors.sol";
import {EvidenceSubmitted} from "./types/Events.sol";

/**
 * @title RefundRequestEvidence
 * @notice On-chain evidence registry tied to refund requests.
 * @dev Append-only: evidence entries cannot be updated or deleted.
 *      Payer, receiver, and arbiter can each submit IPFS CIDs as evidence entries,
 *      creating a permanent, verifiable audit trail.
 *
 *      Requires a RefundRequest to exist before evidence can be submitted.
 *      Evidence is keyed by (paymentInfoHash, nonce) matching RefundRequest composite keys.
 */
contract RefundRequestEvidence is RefundRequestEvidenceAccess {
    struct Evidence {
        address submitter; // Who submitted (20 bytes)
        SubmitterRole role; // Payer/Receiver/Arbiter (1 byte)
        uint48 timestamp; // Block timestamp (6 bytes)
        string cid; // IPFS CID (variable length, separate slot)
    }

    // ============ Errors ============

    error IndexOutOfBounds();

    // ============ Immutables ============

    /// @notice The RefundRequest contract used to validate prerequisite
    RefundRequest public immutable REFUND_REQUEST;

    // ============ Storage ============

    /// @notice Evidence entries per composite key
    /// compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce))
    mapping(bytes32 => mapping(uint256 => Evidence)) private evidence;

    /// @notice Count of evidence entries per composite key
    mapping(bytes32 => uint256) private evidenceCount;

    // ============ Constructor ============

    constructor(address refundRequest) {
        REFUND_REQUEST = RefundRequest(refundRequest);
    }

    // ============ Write Functions ============

    /// @notice Submit evidence for a refund request
    /// @param paymentInfo PaymentInfo struct identifying the payment
    /// @param nonce Record index identifying which refund request
    /// @param cid IPFS CID pointing to the evidence document
    /// @dev Follows CEI pattern. All external calls in Checks phase are view-only.
    function submitEvidence(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce, string calldata cid)
        external
        operatorNotZero(paymentInfo)
    {
        // === CHECKS ===

        // Validate CID is not empty
        if (bytes(cid).length == 0) revert EmptyCid();

        // Validate caller is payer, receiver, or arbiter (also determines role)
        SubmitterRole role = _checkAccessAndGetRole(paymentInfo);

        // Validate RefundRequest exists
        if (!REFUND_REQUEST.hasRefundRequest(paymentInfo, nonce)) {
            revert RefundRequestRequired();
        }

        // === EFFECTS ===

        // Compute composite key
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));

        // Store evidence
        uint256 index = evidenceCount[compositeKey];
        evidence[compositeKey][index] =
            Evidence({submitter: msg.sender, role: role, timestamp: uint48(block.timestamp), cid: cid});
        evidenceCount[compositeKey] = index + 1;

        // Emit event
        emit EvidenceSubmitted(paymentInfo, nonce, msg.sender, role, cid, index);

        // === INTERACTIONS === (none)
    }

    // ============ View Functions ============

    /// @notice Get a single evidence entry by PaymentInfo, nonce, and index
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index
    /// @param index Evidence index (0-based)
    /// @return The evidence entry
    function getEvidence(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce, uint256 index)
        external
        view
        returns (Evidence memory)
    {
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));

        if (index >= evidenceCount[compositeKey]) revert IndexOutOfBounds();
        return evidence[compositeKey][index];
    }

    /// @notice Get the count of evidence entries for a payment+nonce
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index
    /// @return The number of evidence entries
    function getEvidenceCount(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 nonce)
        external
        view
        returns (uint256)
    {
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));

        return evidenceCount[compositeKey];
    }

    /// @notice Get a paginated batch of evidence entries
    /// @param paymentInfo PaymentInfo struct
    /// @param nonce Record index
    /// @param offset Starting index (0-based)
    /// @param count Maximum number of entries to return
    /// @return entries Array of evidence entries
    /// @return total Total number of evidence entries for this key
    function getEvidenceBatch(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 nonce,
        uint256 offset,
        uint256 count
    ) external view returns (Evidence[] memory entries, uint256 total) {
        PaymentOperator operator = PaymentOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));

        total = evidenceCount[compositeKey];

        if (offset >= total || count == 0) {
            return (new Evidence[](0), total);
        }

        uint256 remaining = total - offset;
        uint256 actualCount = remaining < count ? remaining : count;

        entries = new Evidence[](actualCount);
        for (uint256 i = 0; i < actualCount; i++) {
            entries[i] = evidence[compositeKey][offset + i];
        }

        return (entries, total);
    }
}
