// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.23 <0.9.0;

import {BaseTest} from "./Base.t.sol";
import {RelayProxy} from "../src/simple/main/x402/RelayProxy.sol";
import {Escrow} from "../src/simple/main/escrow/Escrow.sol";

// Interface for calling functions through the proxy
interface IExecuteDeposit {
    function executeDeposit(
        address fromUser,
        uint256 amount,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

contract ExecuteDepositRelayTest is BaseTest {
    IExecuteDeposit public relay;
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 1e6;
    
    function setUp() public override {
        super.setUp();
        address relayAddr = deployRelay();
        relay = IExecuteDeposit(relayAddr);
    }
    
    function test_ExecuteDeposit() public {
        // User has tokens
        token.mint(user, DEPOSIT_AMOUNT);
        
        // Create authorization parameters
        bytes32 nonce = keccak256("test-nonce-1");
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 1 hours;
        
        // Execute deposit via relay proxy
        relay.executeDeposit(
            user,
            DEPOSIT_AMOUNT,
            validAfter,
            validBefore,
            nonce,
            0, // v
            bytes32(0), // r
            bytes32(0)  // s
        );
        
        // Check that deposit was created
        (, Escrow.Deposit[] memory depositData) = escrow.getUserDeposits(user);
        require(depositData.length > 0, "No deposits found");
        uint256 principal = depositData[depositData.length - 1].principal;
        assertEq(principal, DEPOSIT_AMOUNT, "Deposit should be created");
        
        // Check that tokens were transferred to escrow
        assertEq(token.balanceOf(address(escrow)), 0, "Escrow should have no tokens (supplied to pool)");
        assertGt(escrow.totalPrincipal(), 0, "Total principal should be updated");
    }
    
    function test_ExecuteDeposit_MerchantNotRegistered() public {
        address unregisteredMerchant = address(0x9999);
        
        // Deploy relay for unregistered merchant
        address unregisteredRelayAddr = factory.deployRelay(unregisteredMerchant);
        IExecuteDeposit unregisteredRelay = IExecuteDeposit(unregisteredRelayAddr);
        
        token.mint(user, DEPOSIT_AMOUNT);
        bytes32 nonce = keccak256("test-nonce-2");
        
        vm.expectRevert("DepositRelay: Merchant not registered");
        unregisteredRelay.executeDeposit(
            user,
            DEPOSIT_AMOUNT,
            block.timestamp,
            block.timestamp + 1 hours,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
    }
    
    function test_ExecuteDeposit_InvalidNonce() public {
        token.mint(user, DEPOSIT_AMOUNT);
        bytes32 nonce = keccak256("test-nonce-3");
        
        // First execution should work
        relay.executeDeposit(
            user,
            DEPOSIT_AMOUNT,
            block.timestamp,
            block.timestamp + 1 hours,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
        
        // Second execution with same nonce should fail
        token.mint(user, DEPOSIT_AMOUNT);
        vm.expectRevert("DepositRelay: transferWithAuthorization failed - Nonce already used");
        relay.executeDeposit(
            user,
            DEPOSIT_AMOUNT,
            block.timestamp,
            block.timestamp + 1 hours,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
    }
    
    function test_ExecuteDeposit_Expired() public {
        token.mint(user, DEPOSIT_AMOUNT);
        bytes32 nonce = keccak256("test-nonce-4");
        
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 1 hours;
        
        // Fast forward past expiration
        vm.warp(block.timestamp + 2 hours);
        
        vm.expectRevert("DepositRelay: transferWithAuthorization failed - Expired");
        relay.executeDeposit(
            user,
            DEPOSIT_AMOUNT,
            validAfter,
            validBefore,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
    }
    
    function test_ExecuteDeposit_NotYetValid() public {
        token.mint(user, DEPOSIT_AMOUNT);
        bytes32 nonce = keccak256("test-nonce-5");
        
        uint256 validAfter = block.timestamp + 1 hours;
        uint256 validBefore = block.timestamp + 2 hours;
        
        vm.expectRevert("DepositRelay: transferWithAuthorization failed - Not yet valid");
        relay.executeDeposit(
            user,
            DEPOSIT_AMOUNT,
            validAfter,
            validBefore,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
    }
    
    function test_ExecuteDeposit_InsufficientBalance() public {
        // Use a user without tokens
        address userWithoutTokens = address(0xDEAD);
        bytes32 nonce = keccak256("test-nonce-6");
        
        vm.expectRevert("DepositRelay: transferWithAuthorization failed - Insufficient balance");
        relay.executeDeposit(
            userWithoutTokens,
            DEPOSIT_AMOUNT,
            block.timestamp,
            block.timestamp + 1 hours,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
    }
    
    function test_ExecuteDeposit_MultipleDeposits() public {
        uint256 amount1 = 500 * 1e6;
        uint256 amount2 = 300 * 1e6;
        
        token.mint(user, amount1 + amount2);
        
        bytes32 nonce1 = keccak256("test-nonce-7");
        bytes32 nonce2 = keccak256("test-nonce-8");
        
        relay.executeDeposit(
            user,
            amount1,
            block.timestamp,
            block.timestamp + 1 hours,
            nonce1,
            0,
            bytes32(0),
            bytes32(0)
        );
        
        relay.executeDeposit(
            user,
            amount2,
            block.timestamp,
            block.timestamp + 1 hours,
            nonce2,
            0,
            bytes32(0),
            bytes32(0)
        );
        
        assertEq(escrow.totalPrincipal(), amount1 + amount2, "Total principal should be sum of deposits");
    }
}
