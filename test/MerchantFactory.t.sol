// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.23 <0.9.0;

import {BaseTest} from "./Base.t.sol";
import {DepositRelayFactory} from "../src/simple/main/x402/DepositRelayFactory.sol";
import {RelayProxy} from "../src/simple/main/x402/RelayProxy.sol";
import {Escrow} from "../src/simple/main/escrow/Escrow.sol";

contract MerchantFactoryTest is BaseTest {
    function test_DeployRelay() public {
        address relay = factory.deployRelay(merchant);
        
        assertTrue(relay != address(0), "Relay should be created");
        assertEq(factory.getMerchantFromRelay(relay), merchant, "Relay should be mapped to merchant");
    }
    
    function test_DeployRelay_AlreadyDeployed() public {
        address relay1 = factory.deployRelay(merchant);
        address relay2 = factory.deployRelay(merchant);
        
        assertEq(relay1, relay2, "Same merchant should get same relay");
        assertEq(factory.getMerchantFromRelay(relay1), merchant, "Relay should be mapped to merchant");
    }
    
    function test_DeployRelay_MultipleMerchants() public {
        address merchant2 = address(0x9999);
        address arbiter2 = address(0xAAAA);
        
        // Register second merchant (merchant must call it themselves)
        // For testing, use the same vault
        vm.prank(merchant2);
        escrow.registerMerchant(arbiter2, address(vault));
        
        address relay1 = factory.deployRelay(merchant);
        address relay2 = factory.deployRelay(merchant2);
        
        assertTrue(relay1 != relay2, "Different merchants should get different relays");
        assertEq(factory.getMerchantFromRelay(relay1), merchant, "First relay should map to first merchant");
        assertEq(factory.getMerchantFromRelay(relay2), merchant2, "Second relay should map to second merchant");
    }
    
    function test_GetRelayAddress() public {
        address computedRelay = factory.getRelayAddress(merchant);
        address deployedRelay = factory.deployRelay(merchant);
        
        assertEq(computedRelay, deployedRelay, "Computed address should match deployed address");
    }
    
    function test_Factory_ImmutableValues() public {
        assertEq(factory.TOKEN(), address(token), "Token should match");
        assertEq(factory.ESCROW(), address(escrow), "Escrow should match");
        assertTrue(factory.IMPLEMENTATION() != address(0), "Implementation should be deployed");
    }
    
    function test_RelayProxy_Storage() public {
        address relayAddr = deployRelay();
        address payable relayAddrPayable = payable(relayAddr);
        RelayProxy proxy = RelayProxy(relayAddrPayable);
        
        assertEq(proxy.MERCHANT_PAYOUT(), merchant, "Proxy should store merchant payout");
        assertEq(proxy.TOKEN(), address(token), "Proxy should store token address");
        assertEq(proxy.ESCROW(), address(escrow), "Proxy should store escrow address");
        assertEq(proxy.IMPLEMENTATION(), factory.IMPLEMENTATION(), "Proxy should store implementation address");
    }
    
    function test_DeployRelay_ZeroMerchant() public {
        vm.expectRevert("Zero merchant payout");
        factory.deployRelay(address(0));
    }
}
