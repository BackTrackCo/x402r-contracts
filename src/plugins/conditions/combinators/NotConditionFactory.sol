// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ICondition} from "../ICondition.sol";
import {NotCondition} from "./NotCondition.sol";

/**
 * @title NotConditionFactory
 * @notice Factory for deploying NotCondition instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(abi.encodePacked(condition)). Each unique condition gets one canonical negation deployment.
 */
contract NotConditionFactory {
    error ZeroCondition();

    /// @notice Deployed condition addresses
    /// @dev Key: keccak256(abi.encodePacked(condition))
    mapping(bytes32 => address) public conditions;

    /// @notice Emitted when a new NotCondition is deployed
    event NotConditionDeployed(address indexed condition, ICondition indexed wrappedCondition);

    /**
     * @notice Deploy a new NotCondition
     * @param _condition The condition to negate
     * @return condition Address of the deployed condition
     */
    function deploy(ICondition _condition) external returns (address condition) {
        if (address(_condition) == address(0)) revert ZeroCondition();

        bytes32 key = getKey(_condition);

        // Return existing deployment if already deployed
        if (conditions[key] != address(0)) {
            return conditions[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("notCondition", key));
        bytes memory bytecode = abi.encodePacked(type(NotCondition).creationCode, abi.encode(_condition));
        condition = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        conditions[key] = condition;

        emit NotConditionDeployed(condition, _condition);

        // ============ INTERACTIONS ============
        address deployed = address(new NotCondition{salt: salt}(_condition));

        assert(deployed == condition);
    }

    /**
     * @notice Get deployed address for a condition negation
     * @param _condition The condition being negated
     * @return condition Address (address(0) if not deployed)
     */
    function getDeployed(ICondition _condition) external view returns (address condition) {
        return conditions[getKey(_condition)];
    }

    /**
     * @notice Compute the deterministic address for a condition negation (before deployment)
     * @param _condition The condition to negate
     * @return condition Predicted address
     */
    function computeAddress(ICondition _condition) external view returns (address condition) {
        bytes32 key = getKey(_condition);
        bytes32 salt = keccak256(abi.encodePacked("notCondition", key));
        bytes memory bytecode = abi.encodePacked(type(NotCondition).creationCode, abi.encode(_condition));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        condition = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a condition
     * @param _condition The condition to compute key for
     * @return The mapping key
     */
    function getKey(ICondition _condition) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_condition));
    }
}
