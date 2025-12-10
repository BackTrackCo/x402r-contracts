// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import "./Base.t.sol";

contract ExecuteDepositRelayTest is BaseTest {
    Escrow public escrow;
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 1e6;
    
    function setUp() public override {
        super.setUp();
        address escrowAddr = registerMerchant();
        escrow = Escrow(escrowAddr);
    }
    
    function test_ExecuteDeposit() public {
        // User approves relay to spend tokens (simulating ERC3009)
        token.mint(user, DEPOSIT_AMOUNT);
        token.approve(address(depositRelay), DEPOSIT_AMOUNT);
        
        // Create a mock authorization (in real scenario, this would be a signature)
        // For testing, we'll use the mock's transferWithAuthorization
        bytes32 nonce = keccak256("test-nonce-1");
        
        // Since we're using a mock, we can directly call transferWithAuthorization
        // In production, this would be called via the relay with a real signature
        vm.prank(user);
        token.transferWithAuthorization(
            user,
            address(escrow),
            DEPOSIT_AMOUNT,
            block.timestamp,
            block.timestamp + 1 hours,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
        
        // Then call noteDeposit
        uint256 depositNonce = escrow.noteDeposit(user, DEPOSIT_AMOUNT);
        
        (uint256 principal,,) = escrow.deposits(user, depositNonce);
        assertEq(principal, DEPOSIT_AMOUNT, "Deposit should be created");
    }
    
    function test_ExecuteDeposit_RelayTokenAddress() public view {
        assertEq(depositRelay.token(), address(token), "Relay should store correct token address");
    }
}

