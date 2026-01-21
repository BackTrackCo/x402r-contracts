// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IReleaseCondition} from "../../src/commerce-payments/operator/types/IReleaseCondition.sol";

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
     * @param paymentInfoHash Hash of the PaymentInfo struct
     * @return True if approved, false otherwise
     */
    function canRelease(bytes32 paymentInfoHash) external view override returns (bool) {
        return approved[paymentInfoHash];
    }
}
