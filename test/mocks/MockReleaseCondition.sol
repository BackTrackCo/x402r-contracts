// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IReleaseCondition} from "../../src/commerce-payments/operator/types/IReleaseCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title MockReleaseCondition
 * @notice Mock release condition for testing - allows manual approval of releases
 */
contract MockReleaseCondition is IReleaseCondition {
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
     * @notice Check if a payment can be released
     * @param paymentInfo The PaymentInfo struct
     * @param amount The amount being released (unused in mock)
     * @return True if approved, false otherwise
     */
    function canRelease(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount) external view override returns (bool) {
        // Silence unused variable warning
        amount;

        // Use keccak256 of paymentInfo for backward compatibility with existing tests
        bytes32 paymentInfoHash = keccak256(abi.encode(paymentInfo));
        return approved[paymentInfoHash];
    }

    /**
     * @notice Approve a payment using PaymentInfo struct
     * @param paymentInfo The PaymentInfo to approve
     */
    function approvePayment(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        bytes32 paymentInfoHash = keccak256(abi.encode(paymentInfo));
        approved[paymentInfoHash] = true;
    }
}
