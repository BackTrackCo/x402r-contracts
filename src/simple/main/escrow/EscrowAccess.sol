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

