// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IBeforeHook} from "../../src/commerce-payments/operator/types/IBeforeHook.sol";
import {RELEASE} from "../../src/commerce-payments/operator/types/Actions.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @notice Release conditions are not met
error ReleaseLocked();

/**
 * @title MockReleaseCondition
 * @notice Mock release condition for testing - allows manual approval of releases
 * @dev Implements IBeforeHook for the pull model architecture (revert-based)
 *      Only guards RELEASE action - other actions pass through
 */
contract MockReleaseCondition is IBeforeHook {
    mapping(bytes32 => bool) public approved;

    /**
     * @notice Approve a payment for release
     * @param paymentInfoHash The payment to approve
     */
    function approve(bytes32 paymentInfoHash) external {
        approved[paymentInfoHash] = true;
    }

    /**
     * @notice Revoke approval for a payment
     * @param paymentInfoHash The payment to revoke
     */
    function revoke(bytes32 paymentInfoHash) external {
        approved[paymentInfoHash] = false;
    }

    /**
     * @notice Approve a payment using PaymentInfo struct
     * @param paymentInfo The PaymentInfo to approve
     */
    function approvePayment(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        bytes32 paymentInfoHash = keccak256(abi.encode(paymentInfo));
        approved[paymentInfoHash] = true;
    }

    /**
     * @notice Check if release is allowed (revert-based)
     * @dev Only guards RELEASE action - other actions pass through
     * @param action The action being performed
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount (unused)
     * @param caller Caller address (unused)
     */
    function beforeAction(
        bytes4 action,
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external view override {
        // Only guard RELEASE action
        if (action == RELEASE) {
            bytes32 paymentInfoHash = keccak256(abi.encode(paymentInfo));
            if (!approved[paymentInfoHash]) revert ReleaseLocked();
        }
        // Other actions: allow through

        // Silence unused variable warnings
        (amount, caller);
    }
}
