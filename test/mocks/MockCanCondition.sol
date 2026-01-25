// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ICanCondition} from "../../src/commerce-payments/operator/types/ICanCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title MockCanCondition
 * @notice Configurable ICanCondition mock for testing
 * @dev Allows setting return value for can() and tracking specific payment approvals
 */
contract MockCanCondition is ICanCondition {
    bool public defaultCanResult = true;
    mapping(bytes32 => bool) public approved;

    /**
     * @notice Set the default return value for can()
     * @param result The value to return
     */
    function setDefaultCanResult(bool result) external {
        defaultCanResult = result;
    }

    /**
     * @notice Approve a specific payment
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
     * @notice Check if the action is allowed
     * @param paymentInfo The PaymentInfo struct
     * @return True if the action is allowed
     */
    function can(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256, /* amount */
        address /* caller */
    ) external view override returns (bool) {
        bytes32 paymentInfoHash = keccak256(abi.encode(paymentInfo));
        if (approved[paymentInfoHash]) return true;
        return defaultCanResult;
    }
}
