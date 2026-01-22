// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice The escrow period must be greater than zero
error InvalidEscrowPeriod();

/// @notice Release conditions are not met
error ReleaseLocked();

/// @notice Funds are frozen (e.g., during arbitration)
error FundsFrozen();
