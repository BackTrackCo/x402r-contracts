// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.23;

import {DepositRelayFactory} from "./DepositRelayFactory.sol";
import {EscrowAccess} from "../escrow/EscrowAccess.sol";

/**
 * @title MerchantRegistrationRouter
 * @notice Atomically registers merchants and deploys proxies to prevent frontrunning
 * @dev Keeps Escrow decoupled from Factory for reuse in non-x402 setups.
 *      By registering and deploying in one transaction, we eliminate the frontrunning window.
 */
contract MerchantRegistrationRouter {
    DepositRelayFactory public immutable FACTORY;
    EscrowAccess public immutable ESCROW;

    event MerchantRegisteredAndProxyDeployed(
        address indexed merchantPayout,
        address indexed arbiter,
        address indexed relayAddress
    );

    constructor(address _factory, address _escrow) {
        require(_factory != address(0), "Zero factory");
        require(_escrow != address(0), "Zero escrow");
        
        FACTORY = DepositRelayFactory(_factory);
        ESCROW = EscrowAccess(_escrow);
    }

    /**
     * @notice Register merchant and deploy proxy atomically
     * @param arbiter The arbiter address for dispute resolution
     * @return relayAddress The deployed relay proxy address
     * @dev This function:
     *      1. Registers merchant with escrow (reverts if already registered)
     *      2. Deploys proxy via factory (idempotent - safe if already deployed)
     *      
     *      By doing both in one transaction, we eliminate the frontrunning window.
     *      The merchant controls this transaction, so no one can frontrun it.
     */
    function registerMerchantAndDeployProxy(address arbiter) 
        external 
        returns (address) 
    {
        address merchantPayout = msg.sender;
        
        // Step 1: Register with escrow (reverts if already registered)
        // Use registerMerchantFor which accepts merchantPayout but requires msg.sender == merchantPayout
        ESCROW.registerMerchantFor(merchantPayout, arbiter);
        
        // Step 2: Deploy proxy (idempotent - safe to call if already deployed)
        address relayAddress = FACTORY.deployRelay(merchantPayout);
        
        emit MerchantRegisteredAndProxyDeployed(merchantPayout, arbiter, relayAddress);
        
        return relayAddress;
    }

    /**
     * @notice Get relay address for a merchant (view function)
     * @param merchantPayout The merchant's payout address
     * @return The deterministic relay proxy address
     */
    function getRelayAddress(address merchantPayout) external view returns (address) {
        return FACTORY.getRelayAddress(merchantPayout);
    }
}

