// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ICondition} from "../../src/plugins/conditions/ICondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @notice Release conditions are not met
error ReleaseLocked();

/**
 * @title MockReleaseCondition
 * @notice Mock release condition for testing - allows manual approval of releases
 * @dev Implements ICondition - returns bool instead of reverting
 */
contract MockReleaseCondition is ICondition {
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
     * @notice Check if payment release is approved
     * @param paymentInfo PaymentInfo struct
     * @return allowed True if approved
     */
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256, address)
        external
        view
        override
        returns (bool allowed)
    {
        bytes32 paymentInfoHash = keccak256(abi.encode(paymentInfo));
        return approved[paymentInfoHash];
    }
}
