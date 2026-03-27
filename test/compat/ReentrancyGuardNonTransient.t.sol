// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";

/// @dev Minimal contract that uses the reentrancy guard (resolves to the
///      NonTransient drop-in when compiled under the Shanghai profile).
contract GuardedContract is ReentrancyGuardTransient {
    uint256 public counter;

    function guarded() external nonReentrant {
        counter++;
    }

    function guardedView() external view nonReadReentrant returns (uint256) {
        return counter;
    }

    /// @dev Attempts reentrant call to `guarded()` during execution.
    function reenter() external nonReentrant {
        counter++;
        this.guarded();
    }

    /// @dev Attempts read-reentrancy during `nonReentrant` execution.
    function reenterRead() external nonReentrant {
        counter++;
        this.guardedView();
    }
}

contract ReentrancyGuardNonTransientTest is Test {
    GuardedContract internal guard;

    function setUp() public {
        guard = new GuardedContract();
    }

    function test_nonReentrant_succeeds() public {
        guard.guarded();
        assertEq(guard.counter(), 1);
    }

    function test_nonReentrant_blocksReentrancy() public {
        vm.expectRevert(ReentrancyGuardTransient.Reentrancy.selector);
        guard.reenter();
    }

    function test_nonReadReentrant_blocksReadDuringWrite() public {
        vm.expectRevert(ReentrancyGuardTransient.Reentrancy.selector);
        guard.reenterRead();
    }

    function test_errorSelector_matchesSolady() public pure {
        assertEq(ReentrancyGuardTransient.Reentrancy.selector, bytes4(0xab143c06));
    }

    function test_guardResetsAfterCall() public {
        guard.guarded();
        guard.guarded();
        assertEq(guard.counter(), 2);
    }
}
