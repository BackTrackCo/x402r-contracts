// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity >=0.8.23 <0.9.0;

abstract contract EscrowAccess {
    mapping(address merchantPayout => address arbiter) public merchantArbiters;
    mapping(address merchantPayout => bool) public registeredMerchants;

    event MerchantRegistered(address indexed merchantPayout, address indexed arbiter);

    /// @notice Register a merchant with an arbiter
    /// @param arbiter The arbiter address for this merchant
    /// @dev Only the merchant can register itself (msg.sender is used as merchantPayout)
    function registerMerchant(address arbiter) external {
        address merchantPayout = msg.sender;
        _registerMerchantInternal(merchantPayout, arbiter);
    }
    
    /// @notice Register a merchant with an arbiter (for use by routers)
    /// @param merchantPayout The merchant's payout address
    /// @param arbiter The arbiter address for this merchant
    /// @dev Can be called by router. The router is responsible for ensuring
    ///      that only the merchant can trigger registration (router uses msg.sender as merchantPayout)
    function registerMerchantFor(address merchantPayout, address arbiter) external {
        _registerMerchantInternal(merchantPayout, arbiter);
    }
    
    /// @notice Register a merchant with an arbiter (internal helper)
    /// @param merchantPayout The merchant's payout address
    /// @param arbiter The arbiter address for this merchant
    /// @dev Internal function that can be called by router or directly by merchant
    function _registerMerchantInternal(address merchantPayout, address arbiter) internal {
        require(arbiter != address(0), "Zero arbiter");
        require(merchantPayout != address(0), "Zero merchant payout");
        require(!registeredMerchants[merchantPayout], "Already registered");
        
        merchantArbiters[merchantPayout] = arbiter;
        registeredMerchants[merchantPayout] = true;
        
        emit MerchantRegistered(merchantPayout, arbiter);
    }

    /// @notice Get arbiter for a merchant
    /// @param merchantPayout The merchant's payout address
    /// @return The arbiter address
    function getArbiter(address merchantPayout) external view returns (address) {
        return merchantArbiters[merchantPayout];
    }

    /// @notice Modifier to check if sender is merchant or arbiter for a specific merchant
    /// @param merchantPayout The merchant's payout address
    modifier onlyMerchantOrArbiter(address merchantPayout) {
        require(
            msg.sender == merchantPayout || msg.sender == merchantArbiters[merchantPayout],
            "Not merchant or arbiter"
        );
        _;
    }
}

