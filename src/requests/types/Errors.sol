// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

// ============ Request-Specific Errors ============
error ZeroRefundAmount();
error RequestAlreadyExists();
error RequestDoesNotExist();
error RequestNotPending();
error RequestNotApprovable();
error ApproveAmountExceedsRequest();
