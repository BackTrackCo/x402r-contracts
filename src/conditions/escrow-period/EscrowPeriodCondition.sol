// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ICondition} from "../ICondition.sol";
import {EscrowPeriodRecorder} from "./EscrowPeriodRecorder.sol";
import {InvalidRecorder} from "./types/Errors.sol";

/**
 * @title EscrowPeriodCondition
 * @notice ICondition adapter that delegates to EscrowPeriodRecorder.canRelease().
 *
 * @dev Thin wrapper: all logic and trusted ESCROW hash computation lives in the recorder.
 *      Used as the RELEASE_CONDITION slot on PaymentOperator.
 *
 * TRUST ASSUMPTIONS:
 *      - RECORDER: Must be a valid EscrowPeriodRecorder that correctly tracks authorization times
 *        and frozen state. The recorder owns hash computation via its trusted ESCROW reference.
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
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256, address)
        external
        view
        override
        returns (bool allowed)
    {
        return RECORDER.canRelease(paymentInfo);
    }

    // ============ View Functions (convenience wrappers) ============

    /// @notice Get the escrow period from the recorder
    function ESCROW_PERIOD() external view returns (uint256) {
        return RECORDER.ESCROW_PERIOD();
    }

    /// @notice Get the freeze policy from the recorder
    function FREEZE_POLICY() external view returns (address) {
        return address(RECORDER.FREEZE_POLICY());
    }

    /// @notice Get the authorization time for a payment (delegates to recorder)
    function getAuthorizationTime(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (uint256) {
        return RECORDER.getAuthorizationTime(paymentInfo);
    }

    /// @notice Check if a payment is frozen (delegates to recorder)
    function isFrozen(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (bool) {
        return RECORDER.isFrozen(paymentInfo);
    }
}
