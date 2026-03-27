// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice SSTORE-only drop-in for Solady's ReentrancyGuardTransient.
///
/// @dev Used via foundry remapping on pre-Cancun chains (e.g. SKALE Base / Shanghai)
///      where TSTORE/TLOAD opcodes do not exist.
///
///      The storage layout, error selector, and modifier interface match the original
///      exactly so that contracts inheriting ReentrancyGuardTransient compile and
///      behave identically — only the storage mechanism changes (SSTORE vs TSTORE).
///
///      Remapping (in foundry.toml Shanghai profile):
///        solady/utils/ReentrancyGuardTransient.sol=src/compat/ReentrancyGuardNonTransient.sol
abstract contract ReentrancyGuardTransient {
    /// @dev Unauthorized reentrant call.
    error Reentrancy();

    /// @dev Same slot as Solady: `uint32(bytes4(keccak256("Reentrancy()"))) | 1 << 71`.
    uint256 private constant _REENTRANCY_GUARD_SLOT = 0x8000000000ab143c06;

    /// @dev Guards a function from reentrancy.
    modifier nonReentrant() virtual {
        uint256 s = _REENTRANCY_GUARD_SLOT;
        assembly ("memory-safe") {
            if eq(sload(s), address()) {
                mstore(0x00, s) // `Reentrancy()`.
                revert(0x1c, 0x04)
            }
            sstore(s, address())
        }
        _;
        assembly ("memory-safe") {
            sstore(s, s)
        }
    }

    /// @dev Guards a view function from read-only reentrancy.
    modifier nonReadReentrant() virtual {
        uint256 s = _REENTRANCY_GUARD_SLOT;
        assembly ("memory-safe") {
            if eq(sload(s), address()) {
                mstore(0x00, s) // `Reentrancy()`.
                revert(0x1c, 0x04)
            }
        }
        _;
    }

    /// @dev Exists for interface compatibility with child-contract overrides.
    ///      Not called by the modifiers above — always uses SSTORE.
    function _useTransientReentrancyGuardOnlyOnMainnet() internal view virtual returns (bool) {
        return true;
    }
}
