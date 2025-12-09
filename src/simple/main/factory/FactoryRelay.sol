// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./EscrowFactory.sol";

/// @title FactoryRelay
/// @notice Allows merchants to execute factory functions gaslessly via signature
contract FactoryRelay {
    bytes32 public constant REGISTER_MERCHANT_TYPEHASH = keccak256(
        "RegisterMerchant(address factory,address merchantPayout,uint256 nonce,uint256 deadline)"
    );
    
    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    
    bytes32 public immutable DOMAIN_SEPARATOR;
    string public constant NAME = "FactoryRelay";
    string public constant VERSION = "1";
    
    mapping(address => mapping(uint256 => bool)) public usedNonces; // factory => nonce => used

    constructor() {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(NAME)),
                keccak256(bytes(VERSION)),
                chainId,
                address(this)
            )
        );
    }

    /// @notice Execute registerMerchant on behalf of merchant using signature
    /// @param factory The factory contract address
    /// @param merchantPayout The merchant's payout address (must match signer)
    /// @param nonce Unique nonce to prevent replay attacks
    /// @param deadline Signature expiration deadline
    /// @param v Signature v component
    /// @param r Signature r component
    /// @param s Signature s component
    /// @return escrowAddr The address of the created escrow contract
    function executeRegisterMerchant(
        address factory,
        address merchantPayout,
        uint256 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (address escrowAddr) {
        require(block.timestamp <= deadline, "Signature expired");
        require(!usedNonces[factory][nonce], "Nonce already used");
        
        // Verify signature
        bytes32 structHash = keccak256(
            abi.encode(
                REGISTER_MERCHANT_TYPEHASH,
                factory,
                merchantPayout,
                nonce,
                deadline
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );
        
        address signer = ecrecover(hash, v, r, s);
        require(signer == merchantPayout, "Invalid signature");
        
        // Mark nonce as used
        usedNonces[factory][nonce] = true;
        
        // Execute registerMerchant
        return EscrowFactory(factory).registerMerchant(merchantPayout);
    }
}

