// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IHook} from "../IHook.sol";
import {HookCombinator} from "./HookCombinator.sol";

/**
 * @title HookCombinatorFactory
 * @notice Factory for deploying HookCombinator instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(abi.encodePacked(hooks)). Each unique combination gets one canonical deployment.
 */
contract HookCombinatorFactory {
    error EmptyHooks();
    error TooManyHooks();

    /// @notice Maximum hooks allowed (matches HookCombinator.MAX_POST_ACTION_HOOKS)
    uint256 public constant MAX_POST_ACTION_HOOKS = 10;

    /// @notice Deployed combinator addresses
    /// @dev Key: keccak256(abi.encodePacked(hooks))
    mapping(bytes32 => address) public combinators;

    /// @notice Emitted when a new HookCombinator is deployed
    event HookCombinatorDeployed(address indexed combinator, IHook[] hooks);

    /**
     * @notice Deploy a new HookCombinator
     * @param _hooks Array of hooks to combine
     * @return combinator Address of the deployed combinator
     */
    function deploy(IHook[] calldata _hooks) external returns (address combinator) {
        if (_hooks.length == 0) revert EmptyHooks();
        if (_hooks.length > MAX_POST_ACTION_HOOKS) revert TooManyHooks();

        bytes32 key = getKey(_hooks);

        // Return existing deployment if already deployed
        if (combinators[key] != address(0)) {
            return combinators[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("hookCombinator", key));
        bytes memory bytecode = abi.encodePacked(type(HookCombinator).creationCode, abi.encode(_hooks));
        combinator = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        combinators[key] = combinator;

        emit HookCombinatorDeployed(combinator, _hooks);

        // ============ INTERACTIONS ============
        address deployed = address(new HookCombinator{salt: salt}(_hooks));

        assert(deployed == combinator);
    }

    /**
     * @notice Get deployed address for a set of hooks
     * @param _hooks Array of hooks
     * @return combinator Address (address(0) if not deployed)
     */
    function getDeployed(IHook[] calldata _hooks) external view returns (address combinator) {
        return combinators[getKey(_hooks)];
    }

    /**
     * @notice Compute the deterministic address for a set of hooks (before deployment)
     * @param _hooks Array of hooks
     * @return combinator Predicted address
     */
    function computeAddress(IHook[] calldata _hooks) external view returns (address combinator) {
        bytes32 key = getKey(_hooks);
        bytes32 salt = keccak256(abi.encodePacked("hookCombinator", key));
        bytes memory bytecode = abi.encodePacked(type(HookCombinator).creationCode, abi.encode(_hooks));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        combinator = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a set of hooks
     * @param _hooks Array of hooks to compute key for
     * @return The mapping key
     */
    function getKey(IHook[] calldata _hooks) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_hooks));
    }
}
