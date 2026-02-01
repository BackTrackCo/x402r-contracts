// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ICondition} from "../ICondition.sol";
import {OrCondition} from "./OrCondition.sol";

/**
 * @title OrConditionFactory
 * @notice Factory for deploying OrCondition instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(abi.encodePacked(conditions)). Each unique combination gets one canonical deployment.
 */
contract OrConditionFactory {
    error NoConditions();
    error TooManyConditions();

    /// @notice Maximum conditions allowed (matches OrCondition.MAX_CONDITIONS)
    uint256 public constant MAX_CONDITIONS = 10;

    /// @notice Deployed condition addresses
    /// @dev Key: keccak256(abi.encodePacked(conditions))
    mapping(bytes32 => address) public conditions;

    /// @notice Emitted when a new OrCondition is deployed
    event OrConditionDeployed(address indexed condition, ICondition[] conditions);

    /**
     * @notice Deploy a new OrCondition
     * @param _conditions Array of conditions to combine with OR logic
     * @return condition Address of the deployed condition
     */
    function deploy(ICondition[] calldata _conditions) external returns (address condition) {
        if (_conditions.length == 0) revert NoConditions();
        if (_conditions.length > MAX_CONDITIONS) revert TooManyConditions();

        bytes32 key = getKey(_conditions);

        // Return existing deployment if already deployed
        if (conditions[key] != address(0)) {
            return conditions[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("orCondition", key));
        bytes memory bytecode = abi.encodePacked(type(OrCondition).creationCode, abi.encode(_conditions));
        condition = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        conditions[key] = condition;

        emit OrConditionDeployed(condition, _conditions);

        // ============ INTERACTIONS ============
        address deployed = address(new OrCondition{salt: salt}(_conditions));

        assert(deployed == condition);
    }

    /**
     * @notice Get deployed address for a set of conditions
     * @param _conditions Array of conditions
     * @return condition Address (address(0) if not deployed)
     */
    function getDeployed(ICondition[] calldata _conditions) external view returns (address condition) {
        return conditions[getKey(_conditions)];
    }

    /**
     * @notice Compute the deterministic address for a set of conditions (before deployment)
     * @param _conditions Array of conditions
     * @return condition Predicted address
     */
    function computeAddress(ICondition[] calldata _conditions) external view returns (address condition) {
        bytes32 key = getKey(_conditions);
        bytes32 salt = keccak256(abi.encodePacked("orCondition", key));
        bytes memory bytecode = abi.encodePacked(type(OrCondition).creationCode, abi.encode(_conditions));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        condition = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a set of conditions
     * @param _conditions Array of conditions to compute key for
     * @return The mapping key
     */
    function getKey(ICondition[] calldata _conditions) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_conditions));
    }
}
