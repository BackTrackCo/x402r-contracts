// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.23 <0.9.0;

abstract contract EscrowAccess {
    // For backward compatibility with per-merchant escrows
    address public immutable MERCHANT_PAYOUT;
    address public immutable ARBITER;

    // For shared escrow (used by refund extension)
    mapping(address merchantPayout => address arbiter) public merchantArbiters;
    mapping(address merchantPayout => bool) public registeredMerchants;
    mapping(address merchantPayout => address vault) public merchantVaults;

    event MerchantRegistered(address indexed merchantPayout, address indexed arbiter, address indexed vault);

    constructor(address _merchantPayout, address _arbiter) {
        // If both are zero, this is a shared escrow (no per-merchant setup)
        // Otherwise, set up for backward compatibility
        if (_merchantPayout != address(0) && _arbiter != address(0)) {
            MERCHANT_PAYOUT = _merchantPayout;
            ARBITER = _arbiter;
        }
    }

    /// @notice Register a merchant with an arbiter and vault (for shared escrow)
    /// @param arbiter The arbiter address for this merchant
    /// @param vault The ERC4626 vault address for this merchant
    /// @dev Only the merchant can register itself (msg.sender is used as merchantPayout)
    function registerMerchant(address arbiter, address vault) external {
        address merchantPayout = msg.sender;
        require(arbiter != address(0), "Zero arbiter");
        require(vault != address(0), "Zero vault");
        require(merchantPayout != address(0), "Zero merchant payout");
        require(!registeredMerchants[merchantPayout], "Already registered");
        
        merchantArbiters[merchantPayout] = arbiter;
        merchantVaults[merchantPayout] = vault;
        registeredMerchants[merchantPayout] = true;
        
        emit MerchantRegistered(merchantPayout, arbiter, vault);
    }

    /// @notice Get arbiter for a merchant
    /// @param merchantPayout The merchant's payout address
    /// @return The arbiter address
    function getArbiter(address merchantPayout) external view returns (address) {
        return merchantArbiters[merchantPayout];
    }

    modifier onlyMerchant() {
        _onlyMerchant();
        _;
    }

    function _onlyMerchant() internal view {
        // Support both per-merchant (immutable) and shared (mapping) escrows
        if (MERCHANT_PAYOUT != address(0)) {
            require(msg.sender == MERCHANT_PAYOUT, "Not merchant");
        } else {
            // For shared escrow, check if sender is a registered merchant
            // This is a simplified check - in practice, you'd pass merchantPayout as parameter
            revert("Use merchantPayout parameter");
        }
    }

    modifier onlyArbiter() {
        _onlyArbiter();
        _;
    }

    function _onlyArbiter() internal view {
        // Support both per-merchant (immutable) and shared (mapping) escrows
        if (ARBITER != address(0)) {
            require(msg.sender == ARBITER, "Not arbiter");
        } else {
            revert("Use merchantPayout parameter");
        }
    }

    modifier onlyMerchantOrArbiter() {
        _onlyMerchantOrArbiter();
        _;
    }

    function _onlyMerchantOrArbiter() internal view {
        // Support both per-merchant (immutable) and shared (mapping) escrows
        if (MERCHANT_PAYOUT != address(0) && ARBITER != address(0)) {
            require(
                msg.sender == MERCHANT_PAYOUT || msg.sender == ARBITER,
                "Not merchant or arbiter"
            );
        } else {
            revert("Use merchantPayout parameter");
        }
    }

    /// @notice Check if sender is merchant or arbiter for a specific merchant
    /// @param merchantPayout The merchant's payout address
    function _checkMerchantOrArbiter(address merchantPayout) internal view {
        require(
            msg.sender == merchantPayout || msg.sender == merchantArbiters[merchantPayout],
            "Not merchant or arbiter"
        );
    }
}

