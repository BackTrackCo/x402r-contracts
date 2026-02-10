// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice The escrow period must be greater than zero
error InvalidEscrowPeriod();

/// @notice Release conditions are not met
error ReleaseLocked();

/// @notice Escrow period has not passed yet
error EscrowPeriodNotPassed();

/// @notice Payment was not authorized through this condition
error NotAuthorized();

/// @notice Invalid recorder address
error InvalidRecorder();

/// @notice Caller is not authorized
error Unauthorized();
