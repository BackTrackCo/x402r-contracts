// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../escrow/Escrow.sol";

contract EscrowFactory {
    address public immutable token;     // USDC address (chain-specific)
    address public immutable aToken;    // aUSDC address (chain-specific)
    address public immutable pool;      // Aave pool address (chain-specific)

    event MerchantRegistered(
        address merchantPayout,
        address arbiter,
        address escrow
    );

    struct MerchantInfo {
        address escrow;
    }

    mapping(address => MerchantInfo) public merchants;
    
    /// @notice Get escrow address for a merchant
    /// @param merchantPayout The merchant's payout address
    /// @return The escrow contract address
    function getEscrow(address merchantPayout) external view returns (address) {
        return merchants[merchantPayout].escrow;
    }

    constructor(
        address _token,
        address _aToken,
        address _pool
    ) {
        require(_token != address(0), "Zero token");
        require(_aToken != address(0), "Zero aToken");
        require(_pool != address(0), "Zero pool");
        
        token = _token;
        aToken = _aToken;
        pool = _pool;
    }

    function registerMerchant(
        address merchantPayout,
        address arbiter
    ) external returns (address escrowAddr) {
        require(merchantPayout != address(0), "Zero merchant payout");
        require(arbiter != address(0), "Zero arbiter");
        require(
            merchants[merchantPayout].escrow == address(0),
            "Already registered"
        );

        // Create escrow with merchant-chosen arbiter (release delay is hardcoded to 3 days)
        // Token, aToken, and pool are set at factory construction (chain-specific)
        Escrow escrow = new Escrow(
            merchantPayout,
            arbiter,
            token,
            aToken,
            pool
        );

        merchants[merchantPayout] = MerchantInfo({
            escrow: address(escrow)
        });

        emit MerchantRegistered(
            merchantPayout,
            arbiter,
            address(escrow)
        );

        return address(escrow);
    }
}

