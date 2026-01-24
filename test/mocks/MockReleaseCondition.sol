// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IReleaseCondition} from "../../src/commerce-payments/operator/types/IReleaseCondition.sol";
import {ArbitrationOperator} from "../../src/commerce-payments/operator/arbitration/ArbitrationOperator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @notice Release conditions are not met
error ReleaseLocked();

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
     * @notice Release funds by calling the operator (push model)
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to release
     */
    function release(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount) external override {
        // Silence unused variable warning
        amount;

        bytes32 paymentInfoHash = keccak256(abi.encode(paymentInfo));
        if (!approved[paymentInfoHash]) {
            revert ReleaseLocked();
        }

        ArbitrationOperator(paymentInfo.operator).release(paymentInfo, amount);
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
