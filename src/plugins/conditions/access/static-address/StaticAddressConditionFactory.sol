// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {StaticAddressCondition} from "./StaticAddressCondition.sol";

/**
 * @title StaticAddressConditionFactory
 * @notice Factory for deploying StaticAddressCondition instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(designatedAddress). Each unique address gets one canonical deployment.
 */
contract StaticAddressConditionFactory {
    error ZeroAddress();

    /// @notice Deployed condition addresses
    /// @dev Key: keccak256(abi.encodePacked(designatedAddress))
    mapping(bytes32 => address) public conditions;

    /// @notice Emitted when a new condition is deployed
    event StaticAddressConditionDeployed(address indexed condition, address indexed designatedAddress);

    /**
     * @notice Deploy a new StaticAddressCondition
     * @param designatedAddress The address allowed to pass the condition check
     * @return condition Address of the deployed condition
     */
    function deploy(address designatedAddress) external returns (address condition) {
        if (designatedAddress == address(0)) revert ZeroAddress();

        bytes32 key = getKey(designatedAddress);

        // Return existing deployment if already deployed
        if (conditions[key] != address(0)) {
            return conditions[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("staticAddressCondition", key));
        bytes memory bytecode =
            abi.encodePacked(type(StaticAddressCondition).creationCode, abi.encode(designatedAddress));
        condition = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        conditions[key] = condition;

        emit StaticAddressConditionDeployed(condition, designatedAddress);

        // ============ INTERACTIONS ============
        address deployed = address(new StaticAddressCondition{salt: salt}(designatedAddress));

        assert(deployed == condition);
    }

    /**
     * @notice Get deployed address for a designated address
     * @param designatedAddress The address the condition checks for
     * @return condition Address (address(0) if not deployed)
     */
    function getDeployed(address designatedAddress) external view returns (address condition) {
        return conditions[getKey(designatedAddress)];
    }

    /**
     * @notice Compute the deterministic address for a designated address (before deployment)
     * @param designatedAddress The address the condition checks for
     * @return condition Predicted address
     */
    function computeAddress(address designatedAddress) external view returns (address condition) {
        bytes32 key = getKey(designatedAddress);
        bytes32 salt = keccak256(abi.encodePacked("staticAddressCondition", key));
        bytes memory bytecode =
            abi.encodePacked(type(StaticAddressCondition).creationCode, abi.encode(designatedAddress));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        condition = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a designated address
     * @param designatedAddress The address to compute key for
     * @return The mapping key
     */
    function getKey(address designatedAddress) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(designatedAddress));
    }
}
