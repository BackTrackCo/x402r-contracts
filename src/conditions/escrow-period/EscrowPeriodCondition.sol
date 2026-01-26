// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ICondition} from "../ICondition.sol";
import {EscrowPeriodRecorder} from "./EscrowPeriodRecorder.sol";
import {InvalidRecorder} from "./types/Errors.sol";

/// @notice Forward declaration for reading escrow from operator
interface IArbitrationOperator {
    function ESCROW() external view returns (AuthCaptureEscrow);
}

/**
 * @title EscrowPeriodCondition
 * @notice ICondition that checks if the escrow period has passed and payment is not frozen.
 *         Reads state from an associated EscrowPeriodRecorder.
 *
 * @dev This contract is stateless - all state is read from the RECORDER.
 *      Used as the RELEASE_CONDITION slot in ArbitrationOperator.
 *      Returns true if:
 *        1. Payment was authorized (authorizationTime > 0)
 *        2. Payment is not frozen
 *        3. Escrow period has passed (block.timestamp >= authTime + ESCROW_PERIOD)
 *
 * TRUST ASSUMPTIONS:
 *      - RECORDER: Must be a valid EscrowPeriodRecorder that correctly tracks authorization times
 *        and frozen state. The condition reads all state from the recorder.
 *      - Timestamp: Uses block.timestamp for time-based escrow periods.
 */
contract EscrowPeriodCondition is ICondition {
    /// @notice The recorder that stores authorization times and frozen state
    EscrowPeriodRecorder public immutable RECORDER;

    constructor(address _recorder) {
        if (_recorder == address(0)) revert InvalidRecorder();
        RECORDER = EscrowPeriodRecorder(_recorder);
    }

    /**
     * @notice Check if funds can be released (escrow period passed and not frozen)
     * @param paymentInfo PaymentInfo struct
     * @return allowed True if escrow period has passed and payment is not frozen
     */
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, address)
        external
        view
        override
        returns (bool allowed)
    {
        AuthCaptureEscrow escrow = IArbitrationOperator(paymentInfo.operator).ESCROW();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Check if frozen (and freeze hasn't expired)
        if (RECORDER.frozenUntil(paymentInfoHash) > block.timestamp) {
            return false;
        }

        // Check if payment was authorized (record() was called)
        uint256 authTime = RECORDER.authorizationTimes(paymentInfoHash);
        if (authTime == 0) {
            return false;
        }

        // Check if escrow period has passed
        if (block.timestamp < authTime + RECORDER.ESCROW_PERIOD()) {
            return false;
        }

        return true;
    }

    // ============ View Functions (convenience wrappers) ============

    /**
     * @notice Get the escrow period from the recorder
     * @return The escrow period in seconds
     */
    function ESCROW_PERIOD() external view returns (uint256) {
        return RECORDER.ESCROW_PERIOD();
    }

    /**
     * @notice Get the freeze policy from the recorder
     * @return The freeze policy address
     */
    function FREEZE_POLICY() external view returns (address) {
        return address(RECORDER.FREEZE_POLICY());
    }

    /**
     * @notice Get the authorization time for a payment (delegates to recorder)
     * @param paymentInfo PaymentInfo struct
     * @return The timestamp when the payment was authorized
     */
    function getAuthorizationTime(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (uint256) {
        return RECORDER.getAuthorizationTime(paymentInfo);
    }

    /**
     * @notice Check if a payment is frozen (delegates to recorder)
     * @param paymentInfo PaymentInfo struct
     * @return True if the payment is frozen
     */
    function isFrozen(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (bool) {
        return RECORDER.isFrozen(paymentInfo);
    }
}
