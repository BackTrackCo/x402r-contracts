// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IRecorder} from "../IRecorder.sol";
import {RecorderCombinator} from "./RecorderCombinator.sol";

/**
 * @title RecorderCombinatorFactory
 * @notice Factory for deploying RecorderCombinator instances with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Key is keccak256(abi.encodePacked(recorders)). Each unique combination gets one canonical deployment.
 */
contract RecorderCombinatorFactory {
    error EmptyRecorders();
    error TooManyRecorders();

    /// @notice Maximum recorders allowed (matches RecorderCombinator.MAX_RECORDERS)
    uint256 public constant MAX_RECORDERS = 10;

    /// @notice Deployed combinator addresses
    /// @dev Key: keccak256(abi.encodePacked(recorders))
    mapping(bytes32 => address) public combinators;

    /// @notice Emitted when a new RecorderCombinator is deployed
    event RecorderCombinatorDeployed(address indexed combinator, IRecorder[] recorders);

    /**
     * @notice Deploy a new RecorderCombinator
     * @param _recorders Array of recorders to combine
     * @return combinator Address of the deployed combinator
     */
    function deploy(IRecorder[] calldata _recorders) external returns (address combinator) {
        if (_recorders.length == 0) revert EmptyRecorders();
        if (_recorders.length > MAX_RECORDERS) revert TooManyRecorders();

        bytes32 key = getKey(_recorders);

        // Return existing deployment if already deployed
        if (combinators[key] != address(0)) {
            return combinators[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("recorderCombinator", key));
        bytes memory bytecode = abi.encodePacked(type(RecorderCombinator).creationCode, abi.encode(_recorders));
        combinator = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        combinators[key] = combinator;

        emit RecorderCombinatorDeployed(combinator, _recorders);

        // ============ INTERACTIONS ============
        address deployed = address(new RecorderCombinator{salt: salt}(_recorders));

        assert(deployed == combinator);
    }

    /**
     * @notice Get deployed address for a set of recorders
     * @param _recorders Array of recorders
     * @return combinator Address (address(0) if not deployed)
     */
    function getDeployed(IRecorder[] calldata _recorders) external view returns (address combinator) {
        return combinators[getKey(_recorders)];
    }

    /**
     * @notice Compute the deterministic address for a set of recorders (before deployment)
     * @param _recorders Array of recorders
     * @return combinator Predicted address
     */
    function computeAddress(IRecorder[] calldata _recorders) external view returns (address combinator) {
        bytes32 key = getKey(_recorders);
        bytes32 salt = keccak256(abi.encodePacked("recorderCombinator", key));
        bytes memory bytecode = abi.encodePacked(type(RecorderCombinator).creationCode, abi.encode(_recorders));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        combinator = address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a set of recorders
     * @param _recorders Array of recorders to compute key for
     * @return The mapping key
     */
    function getKey(IRecorder[] calldata _recorders) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_recorders));
    }
}
