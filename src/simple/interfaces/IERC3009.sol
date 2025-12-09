// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IERC3009
/// @notice Interface for ERC-3009 Transfer with Authorization
/// @dev Allows gasless token transfers via signature
interface IERC3009 {
    /// @notice Transfer tokens using an authorization signature
    /// @param from The address to transfer from
    /// @param to The address to transfer to
    /// @param value The amount to transfer
    /// @param validAfter The timestamp after which this authorization is valid
    /// @param validBefore The timestamp before which this authorization is valid
    /// @param nonce The nonce to prevent replay attacks
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

