// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AlreadyRegistered, NotRegistered, EmptyUri} from "./types/Errors.sol";
import {ArbiterRegistered, ArbiterUriUpdated, ArbiterDeregistered} from "./types/Events.sol";

/// @title ArbiterRegistry
/// @notice On-chain registry for x402r arbiters to advertise their services
/// @dev The URI can point to any location with arbiter metadata:
///      - API endpoint (https://arbiter.example.com/api/disputes)
///      - IPFS metadata (ipfs://Qm...)
///      - Any other resolvable URI
contract ArbiterRegistry {
    // ============ Storage ============

    /// @notice Mapping from arbiter address to their URI
    mapping(address => string) private _arbiterUris;

    /// @notice Array of registered arbiter addresses for enumeration
    address[] private _arbiters;

    /// @notice Mapping from arbiter address to their index in _arbiters array (1-indexed)
    /// @dev 0 means not registered, 1 means index 0, etc.
    mapping(address => uint256) private _arbiterIndex;

    // ============ External Functions ============

    /// @notice Register as an arbiter with a URI
    /// @param uri The URI pointing to arbiter metadata/API endpoint
    function register(string calldata uri) external {
        // Checks
        if (_arbiterIndex[msg.sender] != 0) {
            revert AlreadyRegistered();
        }
        if (bytes(uri).length == 0) {
            revert EmptyUri();
        }

        // Effects
        _arbiterUris[msg.sender] = uri;
        _arbiters.push(msg.sender);
        _arbiterIndex[msg.sender] = _arbiters.length; // 1-indexed

        emit ArbiterRegistered(msg.sender, uri);
    }

    /// @notice Update the URI for a registered arbiter
    /// @param newUri The new URI
    function updateUri(string calldata newUri) external {
        // Checks
        if (_arbiterIndex[msg.sender] == 0) {
            revert NotRegistered();
        }
        if (bytes(newUri).length == 0) {
            revert EmptyUri();
        }

        // Effects
        string memory oldUri = _arbiterUris[msg.sender];
        _arbiterUris[msg.sender] = newUri;

        emit ArbiterUriUpdated(msg.sender, oldUri, newUri);
    }

    /// @notice Deregister as an arbiter
    function deregister() external {
        // Checks
        uint256 index = _arbiterIndex[msg.sender];
        if (index == 0) {
            revert NotRegistered();
        }

        // Effects - swap and pop for O(1) removal
        uint256 lastIndex = _arbiters.length - 1;
        uint256 targetIndex = index - 1; // Convert to 0-indexed

        if (targetIndex != lastIndex) {
            address lastArbiter = _arbiters[lastIndex];
            _arbiters[targetIndex] = lastArbiter;
            _arbiterIndex[lastArbiter] = index; // Keep 1-indexed
        }

        _arbiters.pop();
        delete _arbiterIndex[msg.sender];
        delete _arbiterUris[msg.sender];

        emit ArbiterDeregistered(msg.sender);
    }

    // ============ View Functions ============

    /// @notice Get the URI for an arbiter
    /// @param arbiter The arbiter address
    /// @return The arbiter's URI (empty string if not registered)
    function getUri(address arbiter) external view returns (string memory) {
        return _arbiterUris[arbiter];
    }

    /// @notice Check if an address is a registered arbiter
    /// @param arbiter The address to check
    /// @return True if registered
    function isRegistered(address arbiter) external view returns (bool) {
        return _arbiterIndex[arbiter] != 0;
    }

    /// @notice Get the total number of registered arbiters
    /// @return The count of registered arbiters
    function arbiterCount() external view returns (uint256) {
        return _arbiters.length;
    }

    /// @notice Get a paginated list of arbiters
    /// @param offset Starting index (0-based)
    /// @param count Number of arbiters to return
    /// @return arbiters Array of arbiter addresses
    /// @return uris Array of corresponding URIs
    /// @return total Total number of registered arbiters
    function getArbiters(uint256 offset, uint256 count)
        external
        view
        returns (address[] memory arbiters, string[] memory uris, uint256 total)
    {
        total = _arbiters.length;

        if (offset >= total) {
            return (new address[](0), new string[](0), total);
        }

        uint256 remaining = total - offset;
        uint256 resultCount = count < remaining ? count : remaining;

        arbiters = new address[](resultCount);
        uris = new string[](resultCount);

        for (uint256 i = 0; i < resultCount; i++) {
            address arbiter = _arbiters[offset + i];
            arbiters[i] = arbiter;
            uris[i] = _arbiterUris[arbiter];
        }
    }
}
