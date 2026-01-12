// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity >=0.8.33 <0.9.0;

import {ArbiterationOperatorAccess} from "../operator/ArbiterationOperatorAccess.sol";
import {ArbiterationOperator} from "../operator/ArbiterationOperator.sol";

/**
 * @title RefundRequestAccess
 * @notice Access control for RefundRequest
 * @dev Provides access control implementation that delegates to ArbiterationOperator
 */
abstract contract RefundRequestAccess is ArbiterationOperatorAccess {
    // Reference to the operator contract (must be set by child contract)
    ArbiterationOperator public immutable OPERATOR;
    
    /**
     * @notice Constructor
     * @param _operator Address of the ArbiterationOperator contract
     */
    constructor(address _operator) {
        require(_operator != address(0), "Zero operator");
        OPERATOR = ArbiterationOperator(_operator);
    }
    
    // Implementation of ArbiterationOperatorAccess abstract functions
    
    /**
     * @notice Get arbiter for a merchant (delegates to operator)
     * @param merchant The merchant address
     * @return The arbiter address
     */
    function getArbiter(address merchant) public view override returns (address) {
        return OPERATOR.getArbiter(merchant);
    }
    
    /**
     * @notice Check if merchant is registered (delegates to operator)
     * @param merchant The merchant address
     * @return Whether the merchant is registered
     */
    function isMerchantRegistered(address merchant) public view override returns (bool) {
        return OPERATOR.isMerchantRegistered(merchant);
    }
    
    /**
     * @notice Get merchant for an authorization (delegates to operator)
     * @param authorizationId The authorization ID
     * @return The merchant address
     */
    function _getMerchantForAuthorization(bytes32 authorizationId) 
        internal 
        view 
        override 
        returns (address) 
    {
        return OPERATOR.getMerchantForAuthorization(authorizationId);
    }
    
    // Escrow status modifiers
    
    /**
     * @notice Internal function to check if authorization is in escrow (not captured)
     * @param authorizationId The authorization ID
     */
    function _onlyInEscrow(bytes32 authorizationId) internal view {
        bool captured = OPERATOR.isCaptured(authorizationId);
        require(!captured, "Authorization already captured, use updateStatusPostEscrow");
    }
    
    /**
     * @notice Modifier to check if authorization is in escrow (not captured)
     * @param authorizationId The authorization ID
     */
    modifier onlyInEscrow(bytes32 authorizationId) {
        _onlyInEscrow(authorizationId);
        _;
    }
    
    /**
     * @notice Internal function to check if authorization is post escrow (captured)
     * @param authorizationId The authorization ID
     */
    function _onlyPostEscrow(bytes32 authorizationId) internal view {
        bool captured = OPERATOR.isCaptured(authorizationId);
        require(captured, "Authorization not captured, use updateStatusInEscrow");
    }
    
    /**
     * @notice Modifier to check if authorization is post escrow (captured)
     * @param authorizationId The authorization ID
     */
    modifier onlyPostEscrow(bytes32 authorizationId) {
        _onlyPostEscrow(authorizationId);
        _;
    }
}

