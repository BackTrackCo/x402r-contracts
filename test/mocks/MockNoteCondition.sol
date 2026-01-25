// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {INoteCondition} from "../../src/commerce-payments/operator/types/INoteCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title MockNoteCondition
 * @notice Configurable INoteCondition mock for testing
 * @dev Records note() calls for verification
 */
contract MockNoteCondition is INoteCondition {
    struct NoteCall {
        bytes32 paymentInfoHash;
        uint256 amount;
        address caller;
        uint256 timestamp;
    }

    NoteCall[] public noteCalls;
    mapping(bytes32 => uint256) public noteCount;

    /**
     * @notice Record that an action occurred
     * @param paymentInfo The PaymentInfo struct
     * @param amount The amount involved
     * @param caller The address that performed the action
     */
    function note(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external override {
        bytes32 paymentInfoHash = keccak256(abi.encode(paymentInfo));
        noteCalls.push(NoteCall({
            paymentInfoHash: paymentInfoHash,
            amount: amount,
            caller: caller,
            timestamp: block.timestamp
        }));
        noteCount[paymentInfoHash]++;
    }

    /**
     * @notice Get the number of note() calls made
     * @return The total number of calls
     */
    function getNoteCallCount() external view returns (uint256) {
        return noteCalls.length;
    }

    /**
     * @notice Get a specific note call
     * @param index The index of the call
     * @return The NoteCall struct
     */
    function getNoteCall(uint256 index) external view returns (NoteCall memory) {
        return noteCalls[index];
    }
}
