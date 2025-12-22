// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {DepositRelay} from "./DepositRelay.sol";
import {RelayProxy} from "./RelayProxy.sol";
import {ICreateX} from "@createx/ICreateX.sol";

/**
 * @title DepositRelayFactory
 * @notice Factory for deploying relay proxies via CREATE3
 * @dev Each merchant gets a deterministic proxy address computed via CREATE3.
 *      Uses CreateX for CREATE3 deployment (no bytecode needed!).
 *      Proxies store all needed data directly (merchantPayout, token, escrow, implementation).
 *      Factory maintains relayToMerchant mapping for external queries.
 */
contract DepositRelayFactory {
    address public immutable TOKEN;
    address public immutable ESCROW;
    address public immutable IMPLEMENTATION;
    ICreateX public immutable CREATEX;

    mapping(address => address) public relayToMerchant;

    event RelayDeployed(address indexed relay, address indexed merchantPayout, uint256 version);

    constructor(address _token, address _escrow, address _createx) {
        require(_token != address(0), "Zero token");
        require(_escrow != address(0), "Zero escrow");
        require(_createx != address(0), "Zero createx");
        
        TOKEN = _token;
        ESCROW = _escrow;
        CREATEX = ICreateX(_createx);
        
        // Deploy shared implementation once
        IMPLEMENTATION = address(new DepositRelay());
    }

    /**
     * @notice Compute CREATE3 address for a merchant's relay proxy
     * @param merchantPayout The merchant's payout address
     * @return The deterministic proxy address
     * @dev Uses CREATE3 via CreateX - no bytecode needed!
     *      Uses factory address + merchantPayout in the salt so that:
     *      - Relay addresses are unique per factory deployment
     *      - Off-chain tools can recompute addresses knowing factory + merchant
     */
    function getRelayAddress(address merchantPayout) public view returns (address) {
        // Include factory address in the salt so different factories can't collide
        bytes32 salt = keccak256(abi.encodePacked(address(this), merchantPayout));
        // CreateX guards the salt in deployCreate3, so we need to apply the same guarding
        // For normal salts (not special patterns), CreateX guards it as: keccak256(abi.encode(salt))
        bytes32 guardedSalt = keccak256(abi.encode(salt));
        // CreateX uses its own address as deployer
        return CREATEX.computeCreate3Address(guardedSalt);
    }

    /**
     * @notice Deploy relay proxy for a merchant (anyone can deploy, CREATE3 is deterministic)
     * @param merchantPayout The merchant's payout address
     * @return The deployed proxy address
     * @dev Uses CREATE3 via CreateX - no bytecode needed!
     */
    function deployRelay(address merchantPayout) external returns (address) {
        require(merchantPayout != address(0), "Zero merchant payout");
        
        address relayAddress = getRelayAddress(merchantPayout);
        
        // Check if already deployed
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(relayAddress)
        }
        
        if (codeSize > 0) {
            // Already deployed, just update mapping if needed
            if (relayToMerchant[relayAddress] == address(0)) {
                relayToMerchant[relayAddress] = merchantPayout;
            }
            return relayAddress;
        }
        
        // Deploy via CREATE3 using CreateX (must use the exact same salt as getRelayAddress)
        bytes32 salt = keccak256(abi.encodePacked(address(this), merchantPayout));
        bytes memory initCode = abi.encodePacked(
            type(RelayProxy).creationCode,
            abi.encode(merchantPayout, TOKEN, ESCROW, IMPLEMENTATION)
        );
        
        address deployedAddress = CREATEX.deployCreate3(salt, initCode);
        require(deployedAddress == relayAddress, "Address mismatch");
        
        relayToMerchant[deployedAddress] = merchantPayout;
        // version is now implicitly encoded by the factory address
        emit RelayDeployed(deployedAddress, merchantPayout, 0);
        
        return deployedAddress;
    }

    /**
     * @notice Get merchant payout address from relay address
     * @param relayAddress The relay proxy address
     * @return The merchant payout address (zero if not found)
     * @dev This is a convenience function for external queries.
     *      The proxy itself stores merchantPayout, so this is mainly for off-chain lookups.
     */
    function getMerchantFromRelay(address relayAddress) external view returns (address) {
        return relayToMerchant[relayAddress];
    }
    
    /**
     * @notice Get CreateX address (for CREATE3 address computation)
     * @return The CreateX contract address
     */
    function getCreateX() external view returns (address) {
        return address(CREATEX);
    }
}

