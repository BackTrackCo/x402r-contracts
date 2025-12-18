// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {BaseTest} from "./Base.t.sol";
import {Escrow} from "../src/simple/main/escrow/Escrow.sol";

contract MerchantFactoryTest is BaseTest {
    function test_RegisterMerchant() public {
        address escrow = registerMerchant();
        
        assertTrue(escrow != address(0), "Escrow should be created");
        assertEq(factory.getEscrow(merchant), escrow, "Escrow should be registered");
    }
    
    function test_RegisterMerchant_AlreadyRegistered() public {
        registerMerchant();
        
        vm.expectRevert("Already registered");
        factory.registerMerchant(merchant, defaultArbiter);
    }
    
    function test_RegisterMerchant_MultipleMerchants() public {
        address merchant2 = address(0x9999);
        
        address escrow1 = registerMerchant();
        address escrow2 = factory.registerMerchant(merchant2, defaultArbiter);
        
        assertTrue(escrow1 != escrow2, "Escrows should be different");
        assertEq(factory.getEscrow(merchant), escrow1, "First escrow should be registered");
        assertEq(factory.getEscrow(merchant2), escrow2, "Second escrow should be registered");
    }
    
    function test_RegisterMerchant_DifferentArbiters() public {
        address arbiter1 = address(0xAAAA);
        address arbiter2 = address(0xBBBB);
        address merchant2 = address(0x9999);
        
        address escrow1 = factory.registerMerchant(merchant, arbiter1);
        address escrow2 = factory.registerMerchant(merchant2, arbiter2);
        
        Escrow escrow1Contract = Escrow(escrow1);
        Escrow escrow2Contract = Escrow(escrow2);
        
        assertEq(escrow1Contract.ARBITER(), arbiter1, "First escrow should have arbiter1");
        assertEq(escrow2Contract.ARBITER(), arbiter2, "Second escrow should have arbiter2");
    }
    
    function test_Factory_ImmutableValues() public view {
        assertEq(factory.TOKEN(), address(token), "Token should match");
        assertEq(factory.A_TOKEN(), address(aToken), "AToken should match");
        assertEq(factory.POOL(), address(pool), "Pool should match");
    }
}

