// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IPostActionHook} from "../IPostActionHook.sol";
import {PostActionHookCombinator} from "./PostActionHookCombinator.sol";

/**
 * @title PostActionHookCombinatorFactory
 * @notice Factory for deploying PostActionHookCombinator instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(abi.encodePacked(recorders)). Each unique combination gets one canonical deployment.
 */
contract PostActionHookCombinatorFactory {
    error EmptyRecorders();
    error TooManyRecorders();

    /// @notice Maximum recorders allowed (matches PostActionHookCombinator.MAX_POST_ACTION_HOOKS)
    uint256 public constant MAX_POST_ACTION_HOOKS = 10;

    /// @notice Deployed combinator addresses
    /// @dev Key: keccak256(abi.encodePacked(recorders))
    mapping(bytes32 => address) public combinators;

    /// @notice Emitted when a new PostActionHookCombinator is deployed
    event PostActionHookCombinatorDeployed(address indexed combinator, IPostActionHook[] recorders);

    /**
     * @notice Deploy a new PostActionHookCombinator
     * @param _recorders Array of recorders to combine
     * @return combinator Address of the deployed combinator
     */
    function deploy(IPostActionHook[] calldata _recorders) external returns (address combinator) {
        if (_recorders.length == 0) revert EmptyRecorders();
        if (_recorders.length > MAX_POST_ACTION_HOOKS) revert TooManyRecorders();

        bytes32 key = getKey(_recorders);

        // Return existing deployment if already deployed
        if (combinators[key] != address(0)) {
            return combinators[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("recorderCombinator", key));
        bytes memory bytecode = abi.encodePacked(type(PostActionHookCombinator).creationCode, abi.encode(_recorders));
        combinator = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        combinators[key] = combinator;

        emit PostActionHookCombinatorDeployed(combinator, _recorders);

        // ============ INTERACTIONS ============
        address deployed = address(new PostActionHookCombinator{salt: salt}(_recorders));

        assert(deployed == combinator);
    }

    /**
     * @notice Get deployed address for a set of recorders
     * @param _recorders Array of recorders
     * @return combinator Address (address(0) if not deployed)
     */
    function getDeployed(IPostActionHook[] calldata _recorders) external view returns (address combinator) {
        return combinators[getKey(_recorders)];
    }

    /**
     * @notice Compute the deterministic address for a set of recorders (before deployment)
     * @param _recorders Array of recorders
     * @return combinator Predicted address
     */
    function computeAddress(IPostActionHook[] calldata _recorders) external view returns (address combinator) {
        bytes32 key = getKey(_recorders);
        bytes32 salt = keccak256(abi.encodePacked("recorderCombinator", key));
        bytes memory bytecode = abi.encodePacked(type(PostActionHookCombinator).creationCode, abi.encode(_recorders));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        combinator = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a set of recorders
     * @param _recorders Array of recorders to compute key for
     * @return The mapping key
     */
    function getKey(IPostActionHook[] calldata _recorders) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_recorders));
    }
}
