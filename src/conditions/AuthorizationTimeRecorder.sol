// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {BaseRecorder} from "./BaseRecorder.sol";
import {AuthorizationTimeRecorded} from "./escrow-period/types/Events.sol";

/**
 * @title AuthorizationTimeRecorder
 * @notice Records authorization timestamps for payments.
 * @dev Generic timestamp recording without freeze logic or escrow period constraints.
 *      Use this when you need simple timestamp tracking for analytics, time-based queries,
 *      or external integrations.
 *
 *      For escrow period + freeze functionality: use EscrowPeriodRecorder (extends this contract).
 *
 * GAS COST: ~5k per authorization (single storage write)
 *
 * USAGE:
 *   // Standalone: just timestamp tracking
 *   AuthorizationTimeRecorder timeRecorder = new AuthorizationTimeRecorder(address(escrow));
 *   operator = factory.deployOperator({
 *       authorizeRecorder: address(timeRecorder),
 *       ...
 *   });
 *
 *   // Combined with indexing: use RecorderCombinator
 *   RecorderCombinator combinator = new RecorderCombinator([
 *       address(paymentIndexRecorder),  // hash + amount
 *       address(timeRecorder)            // timestamps
 *   ]);
 */
contract AuthorizationTimeRecorder is BaseRecorder {
    /// @notice Stores the authorization time for each payment
    /// @dev Key: paymentInfoHash, Value: block.timestamp when authorized
    mapping(bytes32 => uint256) public authorizationTimes;

    constructor(address escrow, bytes32 authorizedCodehash) BaseRecorder(escrow, authorizedCodehash) {}

    // ============ IRecorder Implementation ============

    /**
     * @notice Record authorization time for a payment
     * @dev Called by the operator after a payment is authorized.
     *      Verifies operator identity and payment existence via BaseRecorder._verifyAndHash().
     * @param paymentInfo PaymentInfo struct
     */
    function record(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256, address) external virtual override {
        bytes32 paymentInfoHash = _verifyAndHash(paymentInfo);

        authorizationTimes[paymentInfoHash] = block.timestamp;

        emit AuthorizationTimeRecorded(paymentInfo, block.timestamp);
    }

    // ============ View Functions ============

    /**
     * @notice Get the authorization time for a payment
     * @param paymentInfo PaymentInfo struct
     * @return The timestamp when the payment was authorized (0 if not authorized through this recorder)
     */
    function getAuthorizationTime(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (uint256) {
        return authorizationTimes[_getPaymentHash(paymentInfo)];
    }
}
