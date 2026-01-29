// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {BaseRecorder} from "./BaseRecorder.sol";
import {AuthorizationRecorded} from "../escrow-period/types/Events.sol";

/**
 * @title AuthorizationTimeRecorder
 * @notice Records authorization timestamps for payments.
 * @dev Generic recording without escrow period constraints.
 *      Use this when you need timestamp tracking for analytics, time-based queries,
 *      or external integrations.
 *
 *      For escrow period + condition functionality: use EscrowPeriod (extends this contract).
 *
 *      NOTE: The escrow contract only allows one authorization per paymentInfo hash
 *      (hasCollectedPayment flag). To make multiple payments, use different salts.
 *
 *      NOTE: Authorization amount is available from escrow's PaymentAuthorized event
 *      or escrow.paymentState(hash).capturableAmount (which changes over time).
 *
 * GAS COST: ~20k per authorization (one storage slot for timestamp)
 *
 * USAGE:
 *   // Standalone: just timestamp tracking
 *   AuthorizationTimeRecorder recorder = new AuthorizationTimeRecorder(address(escrow), bytes32(0));
 *   operator = factory.deployOperator({
 *       authorizeRecorder: address(recorder),
 *       ...
 *   });
 */
contract AuthorizationTimeRecorder is BaseRecorder {
    /// @notice Stores the authorization timestamp for each payment
    /// @dev Key: paymentInfoHash, Value: block.timestamp when authorized
    ///      Each paymentInfo hash can only be authorized once (escrow enforces this)
    mapping(bytes32 => uint256) public authorizationTimes;

    constructor(address escrow, bytes32 authorizedCodehash) BaseRecorder(escrow, authorizedCodehash) {}

    // ============ IRecorder Implementation ============

    /**
     * @notice Record authorization time for a payment
     * @dev Called by the operator after a payment is authorized.
     *      Verifies operator identity and payment existence via BaseRecorder._verifyAndHash().
     *      Amount and caller are ignored - timestamp is all we need.
     * @param paymentInfo PaymentInfo struct
     */
    function record(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256, address) external virtual override {
        bytes32 paymentInfoHash = _verifyAndHash(paymentInfo);

        // Store authorization timestamp
        authorizationTimes[paymentInfoHash] = block.timestamp;

        emit AuthorizationRecorded(paymentInfo, block.timestamp);
    }

    // ============ View Functions ============

    /**
     * @notice Get the authorization time for a payment
     * @param paymentInfo PaymentInfo struct
     * @return The timestamp when the payment was authorized (0 if not authorized)
     */
    function getAuthorizationTime(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (uint256) {
        return authorizationTimes[_getPaymentHash(paymentInfo)];
    }
}
