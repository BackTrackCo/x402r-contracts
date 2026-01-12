// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity >=0.8.33 <0.9.0;

/**
 * @title ArbiterationOperatorAccess
 * @notice Access control for ArbiterationOperator
 * @dev Provides modifiers for merchant/arbiter access control
 */
abstract contract ArbiterationOperatorAccess {
    // Merchant configuration storage (will be in child contract)
    // This is just the access control logic
    
    // Custom errors (gas-efficient alternative to require strings)
    error MerchantNotRegistered();
    error NotMerchant();
    error NotArbiter();
    error NotPayer();
    error AuthorizationDoesNotExist();
    error NotMerchantOrArbiter();
    
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
     * @notice Internal function to check if sender is merchant or arbiter
     * @param merchant The merchant address
     */
    function _onlyMerchantOrArbiter(address merchant) internal view {
        if (!isMerchantRegistered(merchant)) revert MerchantNotRegistered();
        address arbiter = getArbiter(merchant);
        if (msg.sender != merchant && msg.sender != arbiter) revert NotMerchantOrArbiter();
    }
    
    /**
     * @notice Modifier to check if sender is merchant or arbiter for a specific merchant
     * @param merchant The merchant address
     */
    modifier onlyMerchantOrArbiter(address merchant) {
        _onlyMerchantOrArbiter(merchant);
        _;
    }
    
    /**
     * @notice Internal function to check if sender is merchant
     * @param merchant The merchant address
     */
    function _onlyMerchant(address merchant) internal view {
        if (!isMerchantRegistered(merchant)) revert MerchantNotRegistered();
        if (msg.sender != merchant) revert NotMerchant();
    }
    
    /**
     * @notice Modifier to check if sender is merchant
     * @param merchant The merchant address
     */
    modifier onlyMerchant(address merchant) {
        _onlyMerchant(merchant);
        _;
    }
    
    /**
     * @notice Internal function to check if sender is arbiter
     * @param merchant The merchant address
     */
    function _onlyArbiter(address merchant) internal view {
        if (!isMerchantRegistered(merchant)) revert MerchantNotRegistered();
        address arbiter = getArbiter(merchant);
        if (msg.sender != arbiter) revert NotArbiter();
    }
    
    /**
     * @notice Modifier to check if sender is arbiter for a specific merchant
     * @param merchant The merchant address
     */
    modifier onlyArbiter(address merchant) {
        _onlyArbiter(merchant);
        _;
    }
    
    /**
     * @notice Internal function to check if sender is payer
     * @param payer The payer address
     */
    function _onlyPayer(address payer) internal view {
        if (msg.sender != payer) revert NotPayer();
    }
    
    /**
     * @notice Modifier to check if sender is payer
     * @param payer The payer address
     */
    modifier onlyPayer(address payer) {
        _onlyPayer(payer);
        _;
    }
    
    /**
     * @notice Get merchant for an authorization (must be implemented by child)
     * @param authorizationId The authorization ID
     * @return The merchant address
     */
    function _getMerchantForAuthorization(bytes32 authorizationId) internal view virtual returns (address);
    
    /**
     * @notice Internal function to check if sender is merchant for an authorization
     * @param authorizationId The authorization ID
     */
    function _onlyMerchantForAuthorization(bytes32 authorizationId) internal view {
        address merchant = _getMerchantForAuthorization(authorizationId);
        if (merchant == address(0)) revert AuthorizationDoesNotExist();
        if (!isMerchantRegistered(merchant)) revert MerchantNotRegistered();
        if (msg.sender != merchant) revert NotMerchant();
    }
    
    /**
     * @notice Modifier to check if sender is merchant for an authorization
     * @param authorizationId The authorization ID
     */
    modifier onlyMerchantForAuthorization(bytes32 authorizationId) {
        _onlyMerchantForAuthorization(authorizationId);
        _;
    }
    
    /**
     * @notice Internal function to check if sender is merchant or arbiter for an authorization
     * @param authorizationId The authorization ID
     */
    function _onlyMerchantOrArbiterForAuthorization(bytes32 authorizationId) internal view {
        address merchant = _getMerchantForAuthorization(authorizationId);
        if (merchant == address(0)) revert AuthorizationDoesNotExist();
        if (!isMerchantRegistered(merchant)) revert MerchantNotRegistered();
        address arbiter = getArbiter(merchant);
        if (msg.sender != merchant && msg.sender != arbiter) revert NotMerchantOrArbiter();
    }
    
    /**
     * @notice Modifier to check if sender is merchant or arbiter for an authorization
     * @param authorizationId The authorization ID
     */
    modifier onlyMerchantOrArbiterForAuthorization(bytes32 authorizationId) {
        _onlyMerchantOrArbiterForAuthorization(authorizationId);
        _;
    }
    
    /**
     * @notice Internal function to check if sender is arbiter for an authorization
     * @param authorizationId The authorization ID
     */
    function _onlyArbiterForAuthorization(bytes32 authorizationId) internal view {
        address merchant = _getMerchantForAuthorization(authorizationId);
        if (merchant == address(0)) revert AuthorizationDoesNotExist();
        if (!isMerchantRegistered(merchant)) revert MerchantNotRegistered();
        address arbiter = getArbiter(merchant);
        if (msg.sender != arbiter) revert NotArbiter();
    }
    
    /**
     * @notice Modifier to check if sender is arbiter for an authorization
     * @param authorizationId The authorization ID
     */
    modifier onlyArbiterForAuthorization(bytes32 authorizationId) {
        _onlyArbiterForAuthorization(authorizationId);
        _;
    }
}

