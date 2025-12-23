// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.23 <0.9.0;

import {BaseTest} from "./Base.t.sol";
import {Escrow} from "../src/simple/main/escrow/Escrow.sol";

contract MerchantEscrowTest is BaseTest {
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 1e6; // 1000 USDC
    
    function _getDeposit(address user, uint256 nonce) internal view returns (Escrow.Deposit memory) {
        (uint256[] memory nonces, Escrow.Deposit[] memory deposits) = escrow.getUserDeposits(user);
        for (uint256 i = 0; i < nonces.length; i++) {
            if (nonces[i] == nonce) {
                return deposits[i];
            }
        }
        revert("Deposit not found");
    }
    
    function test_NoteDeposit() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        Escrow.Deposit memory deposit = _getDeposit(user, depositNonce);
        assertEq(deposit.principal, DEPOSIT_AMOUNT, "Principal should match");
        assertEq(deposit.timestamp, block.timestamp, "Timestamp should match");
        assertEq(escrow.totalPrincipal(), DEPOSIT_AMOUNT, "Total principal should match");
    }
    
    function test_NoteDeposit_ZeroUser() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        
        vm.expectRevert("Escrow: Zero user");
        escrow.noteDeposit(address(0), merchant, DEPOSIT_AMOUNT);
    }
    
    function test_NoteDeposit_ZeroAmount() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        
        vm.expectRevert("Escrow: Zero amount");
        escrow.noteDeposit(user, merchant, 0);
    }
    
    function test_NoteDeposit_MultipleDeposits() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT * 2);
        
        uint256 depositNonce1 = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        // Wait a bit and make another deposit
        vm.warp(block.timestamp + 1);
        uint256 depositNonce2 = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        // Both deposits should exist
        Escrow.Deposit memory deposit1 = _getDeposit(user, depositNonce1);
        Escrow.Deposit memory deposit2 = _getDeposit(user, depositNonce2);
        assertEq(deposit1.principal, DEPOSIT_AMOUNT, "First deposit should exist");
        assertEq(deposit2.principal, DEPOSIT_AMOUNT, "Second deposit should exist");
        assertEq(escrow.totalPrincipal(), DEPOSIT_AMOUNT * 2, "Total principal should match");
    }
    
    function test_NoteDeposit_MerchantNotRegistered() public {
        address unregisteredMerchant = address(0x9999);
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        
        vm.expectRevert("Escrow: Merchant not registered");
        escrow.noteDeposit(user, unregisteredMerchant, DEPOSIT_AMOUNT);
    }
    
    function test_Release_TooEarly() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.expectRevert("Too early");
        escrow.release(user, depositNonce);
    }
    
    function test_Release_AfterDelay() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        // Simulate yield accrual - mint yield tokens (principal already in vault from noteDeposit)
        uint256 yield = DEPOSIT_AMOUNT / 100; // 1% yield
        vault.mintUnderlying(yield);
        
        // Fast forward 3 days
        vm.warp(block.timestamp + 3 days + 1);
        
        uint256 merchantBalanceBefore = token.balanceOf(merchant);
        uint256 arbiterBalanceBefore = token.balanceOf(defaultArbiter);
        
        escrow.release(user, depositNonce);
        
        uint256 merchantBalanceAfter = token.balanceOf(merchant);
        uint256 arbiterBalanceAfter = token.balanceOf(defaultArbiter);
        
        assertEq(merchantBalanceAfter - merchantBalanceBefore, DEPOSIT_AMOUNT, "Merchant should receive principal");
        assertGt(arbiterBalanceAfter - arbiterBalanceBefore, 0, "Arbiter should receive yield");
        
        // Check that deposit is cleared (no longer in the list)
        (uint256[] memory nonces, ) = escrow.getUserDeposits(user);
        bool depositFound = false;
        for (uint256 i = 0; i < nonces.length; i++) {
            if (nonces[i] == depositNonce) {
                depositFound = true;
                break;
            }
        }
        assertFalse(depositFound, "Deposit should be cleared");
        assertEq(escrow.totalPrincipal(), 0, "Total principal should be zero");
    }
    
    function test_Refund_OnlyMerchantOrArbiter() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.prank(user);
        vm.expectRevert("Not merchant or arbiter");
        escrow.refund(user, depositNonce);
    }
    
    function test_Refund_ByArbiter() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        // Simulate yield accrual - mint yield tokens (principal already in vault from noteDeposit)
        uint256 yieldAmount = DEPOSIT_AMOUNT / 100; // 1% yield
        vault.mintUnderlying(yieldAmount);
        
        uint256 userBalanceBefore = token.balanceOf(user);
        
        vm.prank(defaultArbiter);
        escrow.refund(user, depositNonce);
        
        uint256 userBalanceAfter = token.balanceOf(user);
        
        assertGe(userBalanceAfter - userBalanceBefore, DEPOSIT_AMOUNT, "User should receive at least principal");
        // Yield goes to arbiter, so user gets principal, arbiter gets yield
        if (userBalanceAfter - userBalanceBefore > DEPOSIT_AMOUNT) {
            // If user got more than principal, that's the yield (shouldn't happen in refund)
            assertEq(userBalanceAfter - userBalanceBefore, DEPOSIT_AMOUNT, "User should only receive principal on refund");
        }
        
        // Check that deposit is cleared (no longer in the list)
        (uint256[] memory nonces, ) = escrow.getUserDeposits(user);
        bool depositFound = false;
        for (uint256 i = 0; i < nonces.length; i++) {
            if (nonces[i] == depositNonce) {
                depositFound = true;
                break;
            }
        }
        assertFalse(depositFound, "Deposit should be cleared");
    }
    
    // Tests for simplified proportional yield calculation (all deposits stay for 3 days)
    
    function test_YieldCalculation_Proportional_SingleDeposit() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        // Add 10% yield - mint yield tokens (principal already in vault from noteDeposit)
        uint256 totalYield = DEPOSIT_AMOUNT / 10; // 100 USDC yield
        vault.mintUnderlying(totalYield);
        
        vm.warp(block.timestamp + 3 days + 1);
        
        uint256 arbiterBalanceBefore = token.balanceOf(defaultArbiter);
        
        escrow.release(user, depositNonce);
        
        uint256 arbiterBalanceAfter = token.balanceOf(defaultArbiter);
        uint256 yieldReceived = arbiterBalanceAfter - arbiterBalanceBefore;
        
        // With single deposit, it should get 100% of yield
        assertEq(yieldReceived, totalYield, "Single deposit should receive all yield");
    }
    
    function test_YieldCalculation_Proportional_TwoEqualDeposits() public {
        address user1 = address(0x1111);
        address user2 = address(0x2222);
        
        uint256 deposit1 = 1000 * 1e6; // 1000 USDC
        uint256 deposit2 = 1000 * 1e6; // 1000 USDC
        
        token.mint(address(escrow), deposit1 + deposit2);
        uint256 depositNonce1 = escrow.noteDeposit(user1, merchant, deposit1);
        uint256 depositNonce2 = escrow.noteDeposit(user2, merchant, deposit2);
        
        // Add 10% yield on total principal - mint yield tokens (principal already in vault from deposits)
        uint256 totalPrincipal = deposit1 + deposit2;
        uint256 totalYield = totalPrincipal / 10; // 200 USDC yield
        vault.mintUnderlying(totalYield);
        
        vm.warp(block.timestamp + 3 days + 1);
        
        uint256 arbiterBalanceBefore = token.balanceOf(defaultArbiter);
        
        // Release first deposit
        escrow.release(user1, depositNonce1);
        
        uint256 arbiterBalanceAfterFirst = token.balanceOf(defaultArbiter);
        uint256 yieldFromFirst = arbiterBalanceAfterFirst - arbiterBalanceBefore;
        
        // First deposit should get 50% of yield (1000 / 2000 = 0.5)
        uint256 expectedYield1 = (totalYield * deposit1) / totalPrincipal;
        assertEq(yieldFromFirst, expectedYield1, "First deposit should get half of yield");
        assertEq(yieldFromFirst, totalYield / 2, "Equal deposits should get equal yield");
        
        // Release second deposit
        escrow.release(user2, depositNonce2);
        
        uint256 arbiterBalanceAfterSecond = token.balanceOf(defaultArbiter);
        uint256 yieldFromSecond = arbiterBalanceAfterSecond - arbiterBalanceAfterFirst;
        
        // Second deposit should also get 50% of yield
        uint256 expectedYield2 = (totalYield * deposit2) / totalPrincipal;
        assertEq(yieldFromSecond, expectedYield2, "Second deposit should get half of yield");
        assertEq(yieldFromSecond, totalYield / 2, "Equal deposits should get equal yield");
        
        // Total yield distributed should equal total yield
        assertEq(yieldFromFirst + yieldFromSecond, totalYield, "Total yield should be fully distributed");
    }
    
    function test_YieldCalculation_Proportional_TwoUnequalDeposits() public {
        address user1 = address(0x1111);
        address user2 = address(0x2222);
        
        uint256 deposit1 = 1000 * 1e6; // 1000 USDC
        uint256 deposit2 = 3000 * 1e6; // 3000 USDC
        
        token.mint(address(escrow), deposit1 + deposit2);
        uint256 depositNonce1 = escrow.noteDeposit(user1, merchant, deposit1);
        uint256 depositNonce2 = escrow.noteDeposit(user2, merchant, deposit2);
        
        // Add 10% yield on total principal - mint yield tokens (principal already in vault from deposits)
        uint256 totalPrincipal = deposit1 + deposit2;
        uint256 totalYield = totalPrincipal / 10; // 400 USDC yield
        vault.mintUnderlying(totalYield);
        
        vm.warp(block.timestamp + 3 days + 1);
        
        uint256 arbiterBalanceBefore = token.balanceOf(defaultArbiter);
        
        // Release first deposit (25% of principal)
        escrow.release(user1, depositNonce1);
        
        uint256 arbiterBalanceAfterFirst = token.balanceOf(defaultArbiter);
        uint256 yieldFromFirst = arbiterBalanceAfterFirst - arbiterBalanceBefore;
        
        // First deposit should get 25% of yield (1000 / 4000 = 0.25)
        uint256 expectedYield1 = (totalYield * deposit1) / totalPrincipal;
        assertEq(yieldFromFirst, expectedYield1, "First deposit should get 25% of yield");
        assertEq(yieldFromFirst, totalYield / 4, "First deposit (25% of principal) should get 25% of yield");
        
        // Release second deposit (75% of principal)
        escrow.release(user2, depositNonce2);
        
        uint256 arbiterBalanceAfterSecond = token.balanceOf(defaultArbiter);
        uint256 yieldFromSecond = arbiterBalanceAfterSecond - arbiterBalanceAfterFirst;
        
        // Second deposit should get 75% of yield (3000 / 4000 = 0.75)
        uint256 expectedYield2 = (totalYield * deposit2) / totalPrincipal;
        assertEq(yieldFromSecond, expectedYield2, "Second deposit should get 75% of yield");
        assertEq(yieldFromSecond, (totalYield * 3) / 4, "Second deposit (75% of principal) should get 75% of yield");
        
        // Total yield distributed should equal total yield
        assertEq(yieldFromFirst + yieldFromSecond, totalYield, "Total yield should be fully distributed");
    }
    
    function test_YieldCalculation_Proportional_ThreeDeposits() public {
        address user1 = address(0x1111);
        address user2 = address(0x2222);
        address user3 = address(0x3333);
        
        uint256 deposit1 = 1000 * 1e6; // 1000 USDC
        uint256 deposit2 = 2000 * 1e6; // 2000 USDC
        uint256 deposit3 = 3000 * 1e6; // 3000 USDC
        
        token.mint(address(escrow), deposit1 + deposit2 + deposit3);
        uint256 depositNonce1 = escrow.noteDeposit(user1, merchant, deposit1);
        uint256 depositNonce2 = escrow.noteDeposit(user2, merchant, deposit2);
        uint256 depositNonce3 = escrow.noteDeposit(user3, merchant, deposit3);
        
        // Add 10% yield on total principal - mint yield tokens (principal already in vault from deposits)
        uint256 totalPrincipal = deposit1 + deposit2 + deposit3;
        uint256 totalYield = totalPrincipal / 10; // 600 USDC yield
        vault.mintUnderlying(totalYield);
        
        vm.warp(block.timestamp + 3 days + 1);
        
        uint256 arbiterBalanceBefore = token.balanceOf(defaultArbiter);
        
        // Release deposits one by one and verify proportional distribution
        escrow.release(user1, depositNonce1);
        uint256 yield1 = token.balanceOf(defaultArbiter) - arbiterBalanceBefore;
        uint256 expectedYield1 = (totalYield * deposit1) / totalPrincipal;
        assertEq(yield1, expectedYield1, "User1 should get proportional yield");
        
        escrow.release(user2, depositNonce2);
        uint256 yield2 = token.balanceOf(defaultArbiter) - arbiterBalanceBefore - yield1;
        uint256 expectedYield2 = (totalYield * deposit2) / totalPrincipal;
        assertEq(yield2, expectedYield2, "User2 should get proportional yield");
        
        escrow.release(user3, depositNonce3);
        uint256 yield3 = token.balanceOf(defaultArbiter) - arbiterBalanceBefore - yield1 - yield2;
        uint256 expectedYield3 = (totalYield * deposit3) / totalPrincipal;
        assertEq(yield3, expectedYield3, "User3 should get proportional yield");
        
        // Total yield should equal sum
        assertEq(yield1 + yield2 + yield3, totalYield, "Total yield should be fully distributed");
    }
    
    function test_YieldCalculation_NoYield() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        // No yield added - vault already has principal from noteDeposit, don't add more
        
        vm.warp(block.timestamp + 3 days + 1);
        
        uint256 arbiterBalanceBefore = token.balanceOf(defaultArbiter);
        
        escrow.release(user, depositNonce);
        
        uint256 arbiterBalanceAfter = token.balanceOf(defaultArbiter);
        
        // Arbiter should receive no yield
        assertEq(arbiterBalanceAfter, arbiterBalanceBefore, "Arbiter should receive no yield when there is none");
    }
    
    function test_YieldCalculation_Refund_Proportional() public {
        address user1 = address(0x1111);
        address user2 = address(0x2222);
        
        uint256 deposit1 = 2000 * 1e6; // 2000 USDC
        uint256 deposit2 = 3000 * 1e6; // 3000 USDC
        
        token.mint(address(escrow), deposit1 + deposit2);
        uint256 depositNonce1 = escrow.noteDeposit(user1, merchant, deposit1);
        escrow.noteDeposit(user2, merchant, deposit2);
        
        // Add yield - mint yield tokens (principal already in vault from deposits)
        uint256 totalPrincipal = deposit1 + deposit2;
        uint256 totalYield = totalPrincipal / 10; // 500 USDC yield
        vault.mintUnderlying(totalYield);
        
        vm.warp(block.timestamp + 3 days + 1);
        
        uint256 arbiterBalanceBefore = token.balanceOf(defaultArbiter);
        
        // Refund first deposit
        vm.prank(defaultArbiter);
        escrow.refund(user1, depositNonce1);
        
        uint256 yieldFromRefund = token.balanceOf(defaultArbiter) - arbiterBalanceBefore;
        uint256 expectedYield = (totalYield * deposit1) / totalPrincipal;
        assertEq(yieldFromRefund, expectedYield, "Refund should distribute yield proportionally");
    }

    function test_Refund_ByMerchant() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        uint256 yieldAmount = DEPOSIT_AMOUNT / 100; // 1% yield
        vault.mintUnderlying(yieldAmount);
        
        uint256 userBalanceBefore = token.balanceOf(user);
        
        vm.prank(merchant);
        escrow.refund(user, depositNonce);
        
        uint256 userBalanceAfter = token.balanceOf(user);
        
        assertEq(userBalanceAfter - userBalanceBefore, DEPOSIT_AMOUNT, "User should receive principal");
        
        // Check that deposit is cleared (no longer in the list)
        (uint256[] memory nonces, ) = escrow.getUserDeposits(user);
        bool depositFound = false;
        for (uint256 i = 0; i < nonces.length; i++) {
            if (nonces[i] == depositNonce) {
                depositFound = true;
                break;
            }
        }
        assertFalse(depositFound, "Deposit should be cleared");
    }
    
    function test_Refund_ByArbiter_StillWorks() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT);
        uint256 depositNonce = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        uint256 yieldAmount = DEPOSIT_AMOUNT / 100;
        vault.accrueYield(yieldAmount);
        // Mint only the yield tokens (principal already in vault from noteDeposit)
        vault.mintUnderlying(yieldAmount);
        
        uint256 userBalanceBefore = token.balanceOf(user);
        
        vm.prank(defaultArbiter);
        escrow.refund(user, depositNonce);
        
        uint256 userBalanceAfter = token.balanceOf(user);
        
        assertEq(userBalanceAfter - userBalanceBefore, DEPOSIT_AMOUNT, "User should receive principal");
    }
    
    function test_MultipleDeposits_RefundSpecificOne() public {
        token.mint(address(escrow), DEPOSIT_AMOUNT * 2);
        
        uint256 depositNonce1 = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        vm.warp(block.timestamp + 1);
        uint256 depositNonce2 = escrow.noteDeposit(user, merchant, DEPOSIT_AMOUNT);
        
        // Refund first deposit - mint yield tokens (principal already in vault from deposits)
        uint256 yieldAmount = DEPOSIT_AMOUNT / 100;
        vault.mintUnderlying(yieldAmount);
        
        vm.prank(merchant);
        escrow.refund(user, depositNonce1);
        
        // Verify first deposit is cleared but second remains
        (uint256[] memory nonces, Escrow.Deposit[] memory deposits) = escrow.getUserDeposits(user);
        bool deposit1Found = false;
        bool deposit2Found = false;
        uint256 deposit2Principal = 0;
        for (uint256 i = 0; i < nonces.length; i++) {
            if (nonces[i] == depositNonce1) {
                deposit1Found = true;
            }
            if (nonces[i] == depositNonce2) {
                deposit2Found = true;
                deposit2Principal = deposits[i].principal;
            }
        }
        assertFalse(deposit1Found, "First deposit should be cleared");
        assertTrue(deposit2Found, "Second deposit should still exist");
        assertEq(deposit2Principal, DEPOSIT_AMOUNT, "Second deposit should still exist");
    }
}
