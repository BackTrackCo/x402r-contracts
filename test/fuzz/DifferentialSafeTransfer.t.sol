// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/**
 * @title DifferentialSafeTransferTest
 * @notice Differential fuzz tests comparing Solady SafeTransferLib vs OpenZeppelin SafeERC20.
 *         Verifies identical behavior for transfer, transferFrom, and approve operations.
 */
contract DifferentialSafeTransferTest is Test {
    using SafeERC20 for IERC20;

    MockERC20 public token;
    address public alice;
    address public bob;

    function setUp() public {
        token = new MockERC20("Test Token", "TEST");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token.mint(alice, type(uint128).max);
        vm.prank(alice);
        token.approve(address(this), type(uint256).max);
    }

    /// @notice Transfer: Solady and OZ should produce identical balance changes
    function testFuzz_DifferentialTransfer(uint128 amount) public {
        amount = uint128(bound(amount, 1, token.balanceOf(alice) / 2));

        // Setup two recipients
        address recipientOZ = makeAddr("recipientOZ");
        address recipientSolady = makeAddr("recipientSolady");

        // Transfer with OZ
        vm.prank(alice);
        IERC20(address(token)).safeTransfer(recipientOZ, amount);

        // Transfer with Solady
        vm.prank(alice);
        SafeTransferLib.safeTransfer(address(token), recipientSolady, amount);

        // Both recipients should have same balance
        assertEq(
            token.balanceOf(recipientOZ),
            token.balanceOf(recipientSolady),
            "OZ and Solady transfer should produce identical balances"
        );
    }

    /// @notice TransferFrom: Solady and OZ should produce identical balance changes
    function testFuzz_DifferentialTransferFrom(uint128 amount) public {
        amount = uint128(bound(amount, 1, token.balanceOf(alice) / 2));

        address recipientOZ = makeAddr("recipientOZ_from");
        address recipientSolady = makeAddr("recipientSolady_from");

        // TransferFrom with OZ
        IERC20(address(token)).safeTransferFrom(alice, recipientOZ, amount);

        // TransferFrom with Solady
        SafeTransferLib.safeTransferFrom(address(token), alice, recipientSolady, amount);

        assertEq(
            token.balanceOf(recipientOZ),
            token.balanceOf(recipientSolady),
            "OZ and Solady transferFrom should produce identical balances"
        );
    }

    /// @notice Approve: Solady and OZ should set identical allowances
    function testFuzz_DifferentialApprove(uint256 amount) public {
        address spenderOZ = makeAddr("spenderOZ");
        address spenderSolady = makeAddr("spenderSolady");

        // Approve with OZ forceApprove (sets directly, not increments)
        vm.prank(alice);
        IERC20(address(token)).forceApprove(spenderOZ, amount);

        // Approve with Solady
        vm.prank(alice);
        SafeTransferLib.safeApprove(address(token), spenderSolady, amount);

        assertEq(
            token.allowance(alice, spenderOZ),
            token.allowance(alice, spenderSolady),
            "OZ and Solady approve should produce identical allowances"
        );
    }

    /// @notice Zero transfer: both should succeed without reverting
    function test_DifferentialZeroTransfer() public {
        address recipientOZ = makeAddr("recipientOZ_zero");
        address recipientSolady = makeAddr("recipientSolady_zero");

        // Transfer 0 with OZ
        vm.prank(alice);
        IERC20(address(token)).safeTransfer(recipientOZ, 0);

        // Transfer 0 with Solady
        vm.prank(alice);
        SafeTransferLib.safeTransfer(address(token), recipientSolady, 0);

        assertEq(token.balanceOf(recipientOZ), 0, "OZ zero transfer should leave balance at 0");
        assertEq(token.balanceOf(recipientSolady), 0, "Solady zero transfer should leave balance at 0");
    }

    /// @notice Insufficient balance: both libraries revert on failed transfers
    function test_DifferentialInsufficientBalance() public {
        address poorUser = makeAddr("poorUser");

        // Verify OZ reverts (use external call wrapper)
        bool ozReverted = false;
        try this.ozTransferExternal(poorUser, alice, 1) {
        // should not reach here
        }
        catch {
            ozReverted = true;
        }
        assertTrue(ozReverted, "OZ should revert on insufficient balance");

        // Verify Solady reverts
        bool soladyReverted = false;
        try this.soladyTransferExternal(poorUser, alice, 1) {
        // should not reach here
        }
        catch {
            soladyReverted = true;
        }
        assertTrue(soladyReverted, "Solady should revert on insufficient balance");
    }

    /// @dev External wrapper for OZ safeTransfer (needed for try/catch)
    function ozTransferExternal(address from, address to, uint256 amount) external {
        vm.prank(from);
        IERC20(address(token)).safeTransfer(to, amount);
    }

    /// @dev External wrapper for Solady safeTransfer (needed for try/catch)
    function soladyTransferExternal(address from, address to, uint256 amount) external {
        vm.prank(from);
        SafeTransferLib.safeTransfer(address(token), to, amount);
    }

    /// @notice Large amount transfer: both handle max uint128 identically
    function test_DifferentialMaxTransfer() public {
        uint256 aliceBalance = token.balanceOf(alice);
        uint256 half = aliceBalance / 2;

        address recipientOZ = makeAddr("recipientOZ_max");
        address recipientSolady = makeAddr("recipientSolady_max");

        vm.prank(alice);
        IERC20(address(token)).safeTransfer(recipientOZ, half);

        vm.prank(alice);
        SafeTransferLib.safeTransfer(address(token), recipientSolady, half);

        assertEq(
            token.balanceOf(recipientOZ),
            token.balanceOf(recipientSolady),
            "Large transfer should produce identical balances"
        );
    }
}
