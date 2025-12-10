// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import "./Base.t.sol";

contract MerchantFactoryRelayTest is BaseTest {
    function test_ExecuteRegisterMerchant() public {
        uint256 nonce = 1;
        uint256 deadline = block.timestamp + 1 hours;
        
        // Use a known private key for merchant
        uint256 merchantKey = 0x5678;
        address merchantAddr = vm.addr(merchantKey);
        merchant = merchantAddr;
        
        // Create signature using EIP-712
        bytes32 structHash = keccak256(
            abi.encode(
                factoryRelay.REGISTER_MERCHANT_TYPEHASH(),
                address(factory),
                merchant,
                defaultArbiter,
                nonce,
                deadline
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", factoryRelay.DOMAIN_SEPARATOR(), structHash)
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(merchantKey, hash);
        
        address escrow = factoryRelay.executeRegisterMerchant(
            address(factory),
            merchant,
            defaultArbiter,
            nonce,
            deadline,
            v,
            r,
            s
        );
        
        assertTrue(escrow != address(0), "Escrow should be created");
        assertEq(factory.getEscrow(merchant), escrow, "Escrow should be registered");
    }
    
    function test_ExecuteRegisterMerchant_InvalidSignature() public {
        uint256 nonce = 2;
        uint256 deadline = block.timestamp + 1 hours;
        
        // Create signature with wrong signer
        bytes32 structHash = keccak256(
            abi.encode(
                factoryRelay.REGISTER_MERCHANT_TYPEHASH(),
                address(factory),
                merchant,
                defaultArbiter,
                nonce,
                deadline
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", factoryRelay.DOMAIN_SEPARATOR(), structHash)
        );
        
        uint256 wrongKey = 0x9999;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, hash);
        
        vm.expectRevert("Invalid signature");
        factoryRelay.executeRegisterMerchant(
            address(factory),
            merchant,
            defaultArbiter,
            nonce,
            deadline,
            v,
            r,
            s
        );
    }
    
    function test_ExecuteRegisterMerchant_ExpiredSignature() public {
        uint256 nonce = 3;
        uint256 deadline = block.timestamp - 1; // Already expired
        
        bytes32 structHash = keccak256(
            abi.encode(
                factoryRelay.REGISTER_MERCHANT_TYPEHASH(),
                address(factory),
                merchant,
                defaultArbiter,
                nonce,
                deadline
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", factoryRelay.DOMAIN_SEPARATOR(), structHash)
        );
        
        uint256 merchantKey = 0x5678;
        address merchantAddr = vm.addr(merchantKey);
        merchant = merchantAddr;
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(merchantKey, hash);
        
        vm.expectRevert("Signature expired");
        factoryRelay.executeRegisterMerchant(
            address(factory),
            merchant,
            defaultArbiter,
            nonce,
            deadline,
            v,
            r,
            s
        );
    }
    
    function test_ExecuteRegisterMerchant_ReplayAttack() public {
        uint256 nonce = 4;
        uint256 deadline = block.timestamp + 1 hours;
        
        // Use a known private key for merchant
        uint256 merchantKey = 0x5678;
        address merchantAddr = vm.addr(merchantKey);
        merchant = merchantAddr;
        
        bytes32 structHash = keccak256(
            abi.encode(
                factoryRelay.REGISTER_MERCHANT_TYPEHASH(),
                address(factory),
                merchant,
                defaultArbiter,
                nonce,
                deadline
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", factoryRelay.DOMAIN_SEPARATOR(), structHash)
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(merchantKey, hash);
        
        // First execution should succeed
        factoryRelay.executeRegisterMerchant(
            address(factory),
            merchant,
            defaultArbiter,
            nonce,
            deadline,
            v,
            r,
            s
        );
        
        // Second execution with same nonce should fail
        vm.expectRevert("Nonce already used");
        factoryRelay.executeRegisterMerchant(
            address(factory),
            merchant,
            defaultArbiter,
            nonce,
            deadline,
            v,
            r,
            s
        );
    }
}

