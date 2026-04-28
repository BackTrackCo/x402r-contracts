// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IPreActionCondition} from "../IPreActionCondition.sol";
import {AndPreActionCondition} from "./AndPreActionCondition.sol";

/**
 * @title AndPreActionConditionFactory
 * @notice Factory for deploying AndPreActionCondition instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(abi.encodePacked(conditions)). Each unique combination gets one canonical deployment.
 */
contract AndPreActionConditionFactory {
    error NoConditions();
    error TooManyConditions();

    /// @notice Maximum conditions allowed (matches AndPreActionCondition.MAX_PRE_ACTION_CONDITIONS)
    uint256 public constant MAX_PRE_ACTION_CONDITIONS = 10;

    /// @notice Deployed condition addresses
    /// @dev Key: keccak256(abi.encodePacked(conditions))
    mapping(bytes32 => address) public conditions;

    /// @notice Emitted when a new AndPreActionCondition is deployed
    event AndPreActionConditionDeployed(address indexed condition, IPreActionCondition[] conditions);

    /**
     * @notice Deploy a new AndPreActionCondition
     * @param _conditions Array of conditions to combine with AND logic
     * @return condition Address of the deployed condition
     */
    function deploy(IPreActionCondition[] calldata _conditions) external returns (address condition) {
        if (_conditions.length == 0) revert NoConditions();
        if (_conditions.length > MAX_PRE_ACTION_CONDITIONS) revert TooManyConditions();

        bytes32 key = getKey(_conditions);

        // Return existing deployment if already deployed
        if (conditions[key] != address(0)) {
            return conditions[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("andCondition", key));
        bytes memory bytecode = abi.encodePacked(type(AndPreActionCondition).creationCode, abi.encode(_conditions));
        condition = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        conditions[key] = condition;

        emit AndPreActionConditionDeployed(condition, _conditions);

        // ============ INTERACTIONS ============
        address deployed = address(new AndPreActionCondition{salt: salt}(_conditions));

        assert(deployed == condition);
    }

    /**
     * @notice Get deployed address for a set of conditions
     * @param _conditions Array of conditions
     * @return condition Address (address(0) if not deployed)
     */
    function getDeployed(IPreActionCondition[] calldata _conditions) external view returns (address condition) {
        return conditions[getKey(_conditions)];
    }

    /**
     * @notice Compute the deterministic address for a set of conditions (before deployment)
     * @param _conditions Array of conditions
     * @return condition Predicted address
     */
    function computeAddress(IPreActionCondition[] calldata _conditions) external view returns (address condition) {
        bytes32 key = getKey(_conditions);
        bytes32 salt = keccak256(abi.encodePacked("andCondition", key));
        bytes memory bytecode = abi.encodePacked(type(AndPreActionCondition).creationCode, abi.encode(_conditions));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        condition = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a set of conditions
     * @param _conditions Array of conditions to compute key for
     * @return The mapping key
     */
    function getKey(IPreActionCondition[] calldata _conditions) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_conditions));
    }
}
