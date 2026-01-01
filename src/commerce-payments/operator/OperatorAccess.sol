// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity >=0.8.23 <0.9.0;

/**
 * @title OperatorAccess
 * @notice Access control for CommercePaymentsOperator
 * @dev Provides modifiers for merchant/arbiter access control
 */
abstract contract OperatorAccess {
    // Merchant configuration storage (will be in child contract)
    // This is just the access control logic
    
    /**
     * @notice Get arbiter for a merchant (must be implemented by child)
     * @param merchant The merchant address
     * @return The arbiter address
     */
    function getArbiter(address merchant) public view virtual returns (address);
    
    /**
     * @notice Check if merchant is registered (must be implemented by child)
     * @param merchant The merchant address
     * @return Whether the merchant is registered
     */
    function isMerchantRegistered(address merchant) public view virtual returns (bool);
    
    /**
     * @notice Modifier to check if sender is merchant or arbiter for a specific merchant
     * @param merchant The merchant address
     */
    modifier onlyMerchantOrArbiter(address merchant) {
        require(isMerchantRegistered(merchant), "Merchant not registered");
        address arbiter = getArbiter(merchant);
        require(
            msg.sender == merchant || msg.sender == arbiter,
            "Not merchant or arbiter"
        );
        _;
    }
    
    /**
     * @notice Modifier to check if sender is merchant
     * @param merchant The merchant address
     */
    modifier onlyMerchant(address merchant) {
        require(isMerchantRegistered(merchant), "Merchant not registered");
        require(msg.sender == merchant, "Not merchant");
        _;
    }
    
    /**
     * @notice Modifier to check if sender is arbiter for a specific merchant
     * @param merchant The merchant address
     */
    modifier onlyArbiter(address merchant) {
        require(isMerchantRegistered(merchant), "Merchant not registered");
        address arbiter = getArbiter(merchant);
        require(msg.sender == arbiter, "Not arbiter");
        _;
    }
    
    /**
     * @notice Modifier to check if sender is payer
     * @param payer The payer address
     */
    modifier onlyPayer(address payer) {
        require(msg.sender == payer, "Not payer");
        _;
    }
    
    /**
     * @notice Get merchant for an authorization (must be implemented by child)
     * @param authorizationId The authorization ID
     * @return The merchant address
     */
    function _getMerchantForAuthorization(bytes32 authorizationId) internal view virtual returns (address);
    
    /**
     * @notice Modifier to check if sender is merchant for an authorization
     * @param authorizationId The authorization ID
     */
    modifier onlyMerchantForAuthorization(bytes32 authorizationId) {
        address merchant = _getMerchantForAuthorization(authorizationId);
        require(merchant != address(0), "Authorization does not exist");
        onlyMerchant(merchant);
        _;
    }
    
    /**
     * @notice Modifier to check if sender is merchant or arbiter for an authorization
     * @param authorizationId The authorization ID
     */
    modifier onlyMerchantOrArbiterForAuthorization(bytes32 authorizationId) {
        address merchant = _getMerchantForAuthorization(authorizationId);
        require(merchant != address(0), "Authorization does not exist");
        onlyMerchantOrArbiter(merchant);
        _;
    }
    
    /**
     * @notice Modifier to check if sender is arbiter for an authorization
     * @param authorizationId The authorization ID
     */
    modifier onlyArbiterForAuthorization(bytes32 authorizationId) {
        address merchant = _getMerchantForAuthorization(authorizationId);
        require(merchant != address(0), "Authorization does not exist");
        onlyArbiter(merchant);
        _;
    }
}

