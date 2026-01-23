// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice The escrow period must be greater than zero
error InvalidEscrowPeriod();

/// @notice Release conditions are not met
error ReleaseLocked();

/// @notice Funds are frozen (e.g., during arbitration)
error FundsFrozen();

/// @notice Escrow period has expired - freezing no longer allowed
error EscrowPeriodExpired();

/// @notice Caller is not authorized for this freeze operation
error UnauthorizedFreeze();

/// @notice Payment is already frozen
error AlreadyFrozen();

/// @notice Payment is not frozen
error NotFrozen();

/// @notice No freeze policy configured
error NoFreezePolicy();
