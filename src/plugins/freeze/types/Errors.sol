// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Freeze window has expired - freezing no longer allowed
error FreezeWindowExpired();

/// @notice Caller is not authorized for this freeze operation
error UnauthorizedFreeze();

/// @notice Payment is already frozen
error AlreadyFrozen();

/// @notice Payment is not frozen
error NotFrozen();
