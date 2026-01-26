// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {PayerFreezePolicy} from "./PayerFreezePolicy.sol";

/**
 * @title PayerFreezePolicyFactory
 * @notice Factory for deploying PayerFreezePolicy instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(freezeDuration).
 */
contract PayerFreezePolicyFactory {
    /// @notice Deployed policy addresses
    /// @dev Key: keccak256(abi.encodePacked(freezeDuration))
    mapping(bytes32 => address) public policies;

    /// @notice Emitted when a new policy is deployed
    event PayerFreezePolicyDeployed(address indexed policy, uint256 freezeDuration);

    /**
     * @notice Deploy a new PayerFreezePolicy
     * @param freezeDuration Duration that payer freezes last (0 = permanent)
     * @return policy Address of the deployed policy
     */
    function deploy(uint256 freezeDuration) external returns (address policy) {
        bytes32 key = getKey(freezeDuration);

        // Return existing deployment if already deployed
        if (policies[key] != address(0)) {
            return policies[key];
        }

        // Deploy policy
        bytes32 salt = keccak256(abi.encodePacked("payerFreezePolicy", key));
        policy = address(new PayerFreezePolicy{salt: salt}(freezeDuration));

        // Store address
        policies[key] = policy;

        emit PayerFreezePolicyDeployed(policy, freezeDuration);
    }

    /**
     * @notice Get deployed address for a freeze duration
     * @param freezeDuration Duration that payer freezes last
     * @return policy Address of the deployed policy (address(0) if not deployed)
     */
    function getDeployed(uint256 freezeDuration) external view returns (address policy) {
        return policies[getKey(freezeDuration)];
    }

    /**
     * @notice Compute the deterministic address for a freeze duration (before deployment)
     * @param freezeDuration Duration that payer freezes last
     * @return policy Predicted address of the policy
     */
    function computeAddress(uint256 freezeDuration) external view returns (address policy) {
        bytes32 key = getKey(freezeDuration);
        bytes32 salt = keccak256(abi.encodePacked("payerFreezePolicy", key));
        bytes memory bytecode = abi.encodePacked(type(PayerFreezePolicy).creationCode, abi.encode(freezeDuration));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        policy = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a freeze duration
     * @param freezeDuration Duration that payer freezes last
     * @return The mapping key
     */
    function getKey(uint256 freezeDuration) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(freezeDuration));
    }
}
