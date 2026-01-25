// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Action identifiers for hook routing
// Used by IBeforeHook and IAfterHook to identify which action is being performed

bytes4 constant AUTHORIZE = bytes4(keccak256("authorize"));
bytes4 constant RELEASE = bytes4(keccak256("release"));
bytes4 constant REFUND_IN_ESCROW = bytes4(keccak256("refundInEscrow"));
bytes4 constant REFUND_POST_ESCROW = bytes4(keccak256("refundPostEscrow"));
