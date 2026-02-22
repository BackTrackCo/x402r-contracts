// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {SignatureCondition} from "./SignatureCondition.sol";

/**
 * @title SignatureConditionFactory
 * @notice Factory for deploying SignatureCondition instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(signer). Each unique signer gets one canonical deployment.
 */
contract SignatureConditionFactory {
    error ZeroSigner();

    /// @notice Deployed condition addresses
    /// @dev Key: keccak256(abi.encodePacked(signer))
    mapping(bytes32 => address) public conditions;

    /// @notice Emitted when a new condition is deployed
    event SignatureConditionDeployed(address indexed condition, address indexed signer);

    /**
     * @notice Deploy a new SignatureCondition for a signer
     * @param signer The address authorized to sign approvals
     * @return condition Address of the deployed condition
     */
    function deploy(address signer) external returns (address condition) {
        if (signer == address(0)) revert ZeroSigner();

        bytes32 key = getKey(signer);

        // Return existing deployment if already deployed
        if (conditions[key] != address(0)) {
            return conditions[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("signatureCondition", key));
        bytes memory bytecode = abi.encodePacked(type(SignatureCondition).creationCode, abi.encode(signer));
        condition = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        conditions[key] = condition;

        emit SignatureConditionDeployed(condition, signer);

        // ============ INTERACTIONS ============
        address deployed = address(new SignatureCondition{salt: salt}(signer));

        assert(deployed == condition);
    }

    /**
     * @notice Get deployed address for a signer
     * @param signer The signer address
     * @return condition Address (address(0) if not deployed)
     */
    function getDeployed(address signer) external view returns (address condition) {
        return conditions[getKey(signer)];
    }

    /**
     * @notice Compute the deterministic address for a signer (before deployment)
     * @param signer The signer address
     * @return condition Predicted address
     */
    function computeAddress(address signer) external view returns (address condition) {
        bytes32 key = getKey(signer);
        bytes32 salt = keccak256(abi.encodePacked("signatureCondition", key));
        bytes memory bytecode = abi.encodePacked(type(SignatureCondition).creationCode, abi.encode(signer));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        condition = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a signer address
     * @param signer The signer to compute key for
     * @return The mapping key
     */
    function getKey(address signer) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(signer));
    }
}
