// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {RefundRequestCondition} from "./RefundRequestCondition.sol";

/**
 * @title RefundRequestConditionFactory
 * @notice Factory for deploying RefundRequestCondition instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev One deployment per arbiter. Key is keccak256(arbiter).
 *      Same pattern as SignatureConditionFactory.
 */
contract RefundRequestConditionFactory {
    error ZeroArbiter();

    /// @notice Deployed condition addresses
    /// @dev Key: keccak256(abi.encodePacked(arbiter))
    mapping(bytes32 => address) public deployments;

    /// @notice Emitted when a new RefundRequestCondition is deployed
    event RefundRequestConditionDeployed(address indexed refundRequestCondition, address indexed arbiter);

    /**
     * @notice Deploy a new RefundRequestCondition for an arbiter
     * @param arbiter The arbiter address
     * @return refundRequestCondition Address of the deployed condition
     */
    function deploy(address arbiter) external returns (address refundRequestCondition) {
        if (arbiter == address(0)) revert ZeroArbiter();

        bytes32 key = getKey(arbiter);

        // Return existing deployment if already deployed
        if (deployments[key] != address(0)) {
            return deployments[key];
        }

        // ============ EFFECTS ============
        bytes32 salt = keccak256(abi.encodePacked("refundRequestCondition", key));
        bytes memory bytecode = abi.encodePacked(type(RefundRequestCondition).creationCode, abi.encode(arbiter));
        refundRequestCondition = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        deployments[key] = refundRequestCondition;

        emit RefundRequestConditionDeployed(refundRequestCondition, arbiter);

        // ============ INTERACTIONS ============
        address deployed = address(new RefundRequestCondition{salt: salt}(arbiter));

        assert(deployed == refundRequestCondition);
    }

    /**
     * @notice Get deployed address for an arbiter
     * @param arbiter The arbiter address
     * @return refundRequestCondition Address (address(0) if not deployed)
     */
    function getDeployed(address arbiter) external view returns (address refundRequestCondition) {
        return deployments[getKey(arbiter)];
    }

    /**
     * @notice Compute the deterministic address for an arbiter (before deployment)
     * @param arbiter The arbiter address
     * @return refundRequestCondition Predicted address
     */
    function computeAddress(address arbiter) external view returns (address refundRequestCondition) {
        bytes32 key = getKey(arbiter);
        bytes32 salt = keccak256(abi.encodePacked("refundRequestCondition", key));
        bytes memory bytecode = abi.encodePacked(type(RefundRequestCondition).creationCode, abi.encode(arbiter));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        refundRequestCondition = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for an arbiter address
     * @param arbiter The arbiter to compute key for
     * @return The mapping key
     */
    function getKey(address arbiter) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(arbiter));
    }
}
