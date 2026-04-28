// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IPreActionCondition} from "../IPreActionCondition.sol";
import {NotPreActionCondition} from "./NotPreActionCondition.sol";

/**
 * @title NotPreActionConditionFactory
 * @notice Factory for deploying NotPreActionCondition instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(abi.encodePacked(condition)). Each unique condition gets one canonical negation deployment.
 */
contract NotPreActionConditionFactory {
    error ZeroCondition();

    /// @notice Deployed condition addresses
    /// @dev Key: keccak256(abi.encodePacked(condition))
    mapping(bytes32 => address) public conditions;

    /// @notice Emitted when a new NotPreActionCondition is deployed
    event NotPreActionConditionDeployed(address indexed condition, IPreActionCondition indexed wrappedCondition);

    /**
     * @notice Deploy a new NotPreActionCondition
     * @param _condition The condition to negate
     * @return condition Address of the deployed condition
     */
    function deploy(IPreActionCondition _condition) external returns (address condition) {
        if (address(_condition) == address(0)) revert ZeroCondition();

        bytes32 key = getKey(_condition);

        // Return existing deployment if already deployed
        if (conditions[key] != address(0)) {
            return conditions[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("notCondition", key));
        bytes memory bytecode = abi.encodePacked(type(NotPreActionCondition).creationCode, abi.encode(_condition));
        condition = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        conditions[key] = condition;

        emit NotPreActionConditionDeployed(condition, _condition);

        // ============ INTERACTIONS ============
        address deployed = address(new NotPreActionCondition{salt: salt}(_condition));

        assert(deployed == condition);
    }

    /**
     * @notice Get deployed address for a condition negation
     * @param _condition The condition being negated
     * @return condition Address (address(0) if not deployed)
     */
    function getDeployed(IPreActionCondition _condition) external view returns (address condition) {
        return conditions[getKey(_condition)];
    }

    /**
     * @notice Compute the deterministic address for a condition negation (before deployment)
     * @param _condition The condition to negate
     * @return condition Predicted address
     */
    function computeAddress(IPreActionCondition _condition) external view returns (address condition) {
        bytes32 key = getKey(_condition);
        bytes32 salt = keccak256(abi.encodePacked("notCondition", key));
        bytes memory bytecode = abi.encodePacked(type(NotPreActionCondition).creationCode, abi.encode(_condition));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        condition = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a condition
     * @param _condition The condition to compute key for
     * @return The mapping key
     */
    function getKey(IPreActionCondition _condition) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_condition));
    }
}
