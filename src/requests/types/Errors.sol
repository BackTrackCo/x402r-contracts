// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

// ============ Request-Specific Errors ============
error ZeroOperator();
error RequestAlreadyExists();
error RequestDoesNotExist();
error RequestNotPending();
error InvalidStatus();
error FullyRefunded();
