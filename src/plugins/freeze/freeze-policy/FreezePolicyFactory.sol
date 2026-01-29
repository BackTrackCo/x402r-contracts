// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {FreezePolicy} from "./FreezePolicy.sol";

/**
 * @title FreezePolicyFactory
 * @notice Factory for deploying FreezePolicy instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(freezeCondition, unfreezeCondition, freezeDuration).
 *
 *      Example configurations:
 *      - Payer freeze/unfreeze (3 days): deploy(PayerCondition, PayerCondition, 3 days)
 *      - Payer freeze, Arbiter unfreeze: deploy(PayerCondition, StaticAddressCondition, 0)
 *      - Anyone freeze, Receiver unfreeze: deploy(AlwaysTrueCondition, ReceiverCondition, 7 days)
 */
contract FreezePolicyFactory {
    /// @notice Deployed policy addresses
    mapping(bytes32 => address) public policies;

    /// @notice Emitted when a new policy is deployed
    event FreezePolicyDeployed(
        address indexed policy, address freezeCondition, address unfreezeCondition, uint256 freezeDuration
    );

    /**
     * @notice Deploy a new FreezePolicy
     * @param freezeCondition ICondition that authorizes freeze calls
     * @param unfreezeCondition ICondition that authorizes unfreeze calls
     * @param freezeDuration Duration that freezes last (0 = permanent)
     * @return policy Address of the deployed policy
     */
    function deploy(address freezeCondition, address unfreezeCondition, uint256 freezeDuration)
        external
        returns (address policy)
    {
        bytes32 key = getKey(freezeCondition, unfreezeCondition, freezeDuration);

        // Return existing deployment if already deployed
        if (policies[key] != address(0)) {
            return policies[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("freezePolicy", key));
        bytes memory bytecode = abi.encodePacked(
            type(FreezePolicy).creationCode, abi.encode(freezeCondition, unfreezeCondition, freezeDuration)
        );
        policy = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        policies[key] = policy;

        emit FreezePolicyDeployed(policy, freezeCondition, unfreezeCondition, freezeDuration);

        // ============ INTERACTIONS ============
        address deployed = address(new FreezePolicy{salt: salt}(freezeCondition, unfreezeCondition, freezeDuration));

        assert(deployed == policy);
    }

    /**
     * @notice Get deployed address for a configuration
     * @param freezeCondition ICondition that authorizes freeze calls
     * @param unfreezeCondition ICondition that authorizes unfreeze calls
     * @param freezeDuration Duration that freezes last
     * @return policy Address (address(0) if not deployed)
     */
    function getDeployed(address freezeCondition, address unfreezeCondition, uint256 freezeDuration)
        external
        view
        returns (address policy)
    {
        return policies[getKey(freezeCondition, unfreezeCondition, freezeDuration)];
    }

    /**
     * @notice Compute the deterministic address for a configuration (before deployment)
     * @param freezeCondition ICondition that authorizes freeze calls
     * @param unfreezeCondition ICondition that authorizes unfreeze calls
     * @param freezeDuration Duration that freezes last
     * @return policy Predicted address
     */
    function computeAddress(address freezeCondition, address unfreezeCondition, uint256 freezeDuration)
        external
        view
        returns (address policy)
    {
        bytes32 key = getKey(freezeCondition, unfreezeCondition, freezeDuration);
        bytes32 salt = keccak256(abi.encodePacked("freezePolicy", key));
        bytes memory bytecode = abi.encodePacked(
            type(FreezePolicy).creationCode, abi.encode(freezeCondition, unfreezeCondition, freezeDuration)
        );
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        policy = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a configuration
     * @param freezeCondition ICondition that authorizes freeze calls
     * @param unfreezeCondition ICondition that authorizes unfreeze calls
     * @param freezeDuration Duration that freezes last
     * @return The mapping key
     */
    function getKey(address freezeCondition, address unfreezeCondition, uint256 freezeDuration)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(freezeCondition, unfreezeCondition, freezeDuration));
    }
}
