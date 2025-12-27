// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.23 <0.9.0;

import {BaseTest} from "./Base.t.sol";
import {MerchantRegistrationRouter} from "../src/simple/main/x402/MerchantRegistrationRouter.sol";
import {DepositRelayFactory} from "../src/simple/main/x402/DepositRelayFactory.sol";
import {Escrow} from "../src/simple/main/escrow/Escrow.sol";
import {RelayProxy} from "../src/simple/main/x402/RelayProxy.sol";

contract MerchantRegistrationRouterTest is BaseTest {
    MerchantRegistrationRouter public router;
    
    function setUp() public override {
        // Don't call super.setUp() - we want to control registration ourselves
        _deployMocks();
        _deployContracts();
        _setupBalances();
        // Don't call _registerMerchant() - we'll test registration via router
        
        // Deploy router
        router = new MerchantRegistrationRouter(
            address(factory),
            address(escrow)
        );
    }
    
    function test_RegisterMerchantAndDeployProxy() public {
        // Use a new merchant that hasn't registered yet
        address newMerchant = address(0x9999);
        address arbiter = address(0xAAAA);
        
        vm.prank(newMerchant);
        address relayAddress = router.registerMerchantAndDeployProxy(arbiter);
        
        // Check merchant is registered
        assertTrue(escrow.registeredMerchants(newMerchant), "Merchant should be registered");
        assertEq(escrow.getArbiter(newMerchant), arbiter, "Arbiter should be set");
        
        // Check proxy is deployed
        assertTrue(relayAddress != address(0), "Relay should be deployed");
        assertEq(factory.getMerchantFromRelay(relayAddress), newMerchant, "Relay should be mapped to merchant");
        
        // Verify proxy storage
        RelayProxy proxy = RelayProxy(payable(relayAddress));
        assertEq(proxy.MERCHANT_PAYOUT(), newMerchant, "Proxy should store merchant payout");
        assertEq(proxy.ESCROW(), address(escrow), "Proxy should store escrow address");
    }
    
    function test_RegisterMerchantAndDeployProxy_AlreadyRegistered() public {
        address newMerchant = address(0x8888);
        address arbiter = address(0xAAAA);
        
        // Register first time
        vm.prank(newMerchant);
        router.registerMerchantAndDeployProxy(arbiter);
        
        // Try to register the same merchant twice
        vm.prank(newMerchant);
        vm.expectRevert();
        router.registerMerchantAndDeployProxy(arbiter);
    }
    
    function test_RegisterMerchantAndDeployProxy_AlreadyDeployed() public {
        address newMerchant1 = address(0x8888);
        address newMerchant2 = address(0x9999);
        address arbiter1 = address(0xBBBB);
        address arbiter2 = address(0xCCCC);
        
        // Register first merchant
        vm.prank(newMerchant1);
        address relay1 = router.registerMerchantAndDeployProxy(arbiter1);
        
        // Register second merchant
        vm.prank(newMerchant2);
        address relay2 = router.registerMerchantAndDeployProxy(arbiter2);
        
        // Should get different relay
        assertTrue(relay1 != relay2, "Different merchants should get different relays");
        assertTrue(relay2 != address(0), "Relay should be deployed");
    }
    
    function test_RegisterMerchantAndDeployProxy_Atomic() public {
        // Test that both registration and deployment happen atomically
        address newMerchant = address(0x7777);
        address arbiter = address(0xCCCC);
        
        // Before: merchant not registered, proxy not deployed
        assertFalse(escrow.registeredMerchants(newMerchant), "Merchant should not be registered");
        address expectedRelay = factory.getRelayAddress(newMerchant);
        uint256 codeSizeBefore;
        assembly {
            codeSizeBefore := extcodesize(expectedRelay)
        }
        assertEq(codeSizeBefore, 0, "Proxy should not be deployed");
        
        // Execute registration and deployment
        vm.prank(newMerchant);
        address relayAddress = router.registerMerchantAndDeployProxy(arbiter);
        
        // After: both should be done
        assertTrue(escrow.registeredMerchants(newMerchant), "Merchant should be registered");
        assertEq(relayAddress, expectedRelay, "Relay address should match");
        uint256 codeSizeAfter;
        assembly {
            codeSizeAfter := extcodesize(relayAddress)
        }
        assertTrue(codeSizeAfter > 0, "Proxy should be deployed");
    }
    
    function test_GetRelayAddress() public {
        address newMerchant = address(0x6666);
        address expectedRelay = factory.getRelayAddress(newMerchant);
        address routerRelay = router.getRelayAddress(newMerchant);
        
        assertEq(routerRelay, expectedRelay, "Router should return same address as factory");
    }
    
    function test_RegisterMerchantAndDeployProxy_ZeroArbiter() public {
        address newMerchant = address(0x5555);
        
        vm.prank(newMerchant);
        vm.expectRevert("Zero arbiter");
        router.registerMerchantAndDeployProxy(address(0));
    }
    
    function test_Router_ImmutableValues() public {
        assertEq(address(router.FACTORY()), address(factory), "Factory should match");
        assertEq(address(router.ESCROW()), address(escrow), "Escrow should match");
    }
    
    function test_Router_Constructor_ZeroFactory() public {
        vm.expectRevert("Zero factory");
        new MerchantRegistrationRouter(address(0), address(escrow));
    }
    
    function test_Router_Constructor_ZeroEscrow() public {
        vm.expectRevert("Zero escrow");
        new MerchantRegistrationRouter(address(factory), address(0));
    }
}

