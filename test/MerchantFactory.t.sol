// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./Base.t.sol";

contract MerchantFactoryTest is BaseTest {
    function test_RegisterMerchant() public {
        address escrow = registerMerchant();
        
        assertTrue(escrow != address(0), "Escrow should be created");
        assertEq(factory.getEscrow(merchant), escrow, "Escrow should be registered");
    }
    
    function test_RegisterMerchant_AlreadyRegistered() public {
        registerMerchant();
        
        vm.expectRevert("Already registered");
        factory.registerMerchant(merchant);
    }
    
    function test_RegisterMerchant_MultipleMerchants() public {
        address merchant2 = address(0x9999);
        
        address escrow1 = registerMerchant();
        address escrow2 = factory.registerMerchant(merchant2);
        
        assertTrue(escrow1 != escrow2, "Escrows should be different");
        assertEq(factory.getEscrow(merchant), escrow1, "First escrow should be registered");
        assertEq(factory.getEscrow(merchant2), escrow2, "Second escrow should be registered");
    }
    
    function test_Factory_ImmutableValues() public view {
        assertEq(factory.defaultArbiter(), defaultArbiter, "Default arbiter should match");
        assertEq(factory.token(), address(token), "Token should match");
        assertEq(factory.aToken(), address(aToken), "AToken should match");
        assertEq(factory.pool(), address(pool), "Pool should match");
    }
}

