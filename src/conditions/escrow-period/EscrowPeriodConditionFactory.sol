// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {EscrowPeriodRecorder} from "./EscrowPeriodRecorder.sol";
import {EscrowPeriodCondition} from "./EscrowPeriodCondition.sol";
import {EscrowPeriodConditionDeployed} from "./types/Events.sol";

/**
 * @title EscrowPeriodConditionFactory
 * @notice Factory for deploying EscrowPeriodRecorder and EscrowPeriodCondition pairs.
 *         Uses CREATE2 for deterministic addresses.
 *
 * @dev Deployment flow:
 *      1. Deploy recorder with (escrowPeriod, freezePolicy)
 *      2. Deploy condition pointing to the recorder
 *      3. Return both addresses
 *
 *      The key for looking up deployed pairs is keccak256(escrowPeriod, freezePolicy).
 */
contract EscrowPeriodConditionFactory {
    /// @notice Deployed recorder addresses
    /// @dev Key: keccak256(abi.encodePacked(escrowPeriod, freezePolicy))
    mapping(bytes32 => address) public recorders;

    /// @notice Deployed condition addresses
    /// @dev Key: keccak256(abi.encodePacked(escrowPeriod, freezePolicy))
    mapping(bytes32 => address) public conditions;

    /**
     * @notice Deploy a new EscrowPeriodRecorder and EscrowPeriodCondition pair
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract (address(0) = no freeze)
     * @return recorder Address of the deployed recorder
     * @return condition Address of the deployed condition
     */
    function deploy(uint256 escrowPeriod, address freezePolicy) external returns (address recorder, address condition) {
        bytes32 key = getKey(escrowPeriod, freezePolicy);

        // Return existing deployment if already deployed
        if (recorders[key] != address(0)) {
            return (recorders[key], conditions[key]);
        }

        // Deploy recorder first (holds state)
        bytes32 recorderSalt = keccak256(abi.encodePacked("recorder", key));
        recorder = address(new EscrowPeriodRecorder{salt: recorderSalt}(escrowPeriod, freezePolicy));

        // Deploy condition pointing to recorder
        bytes32 conditionSalt = keccak256(abi.encodePacked("condition", key));
        condition = address(new EscrowPeriodCondition{salt: conditionSalt}(recorder));

        // Store addresses
        recorders[key] = recorder;
        conditions[key] = condition;

        emit EscrowPeriodConditionDeployed(condition, recorder, escrowPeriod);
    }

    /**
     * @notice Get deployed addresses for a configuration
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract
     * @return recorder Address of the deployed recorder (address(0) if not deployed)
     * @return condition Address of the deployed condition (address(0) if not deployed)
     */
    function getDeployed(uint256 escrowPeriod, address freezePolicy)
        external
        view
        returns (address recorder, address condition)
    {
        bytes32 key = getKey(escrowPeriod, freezePolicy);
        return (recorders[key], conditions[key]);
    }

    /**
     * @notice Compute the deterministic addresses for a configuration (before deployment)
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract
     * @return recorder Predicted address of the recorder
     * @return condition Predicted address of the condition
     */
    function computeAddresses(uint256 escrowPeriod, address freezePolicy)
        external
        view
        returns (address recorder, address condition)
    {
        bytes32 key = getKey(escrowPeriod, freezePolicy);

        // Compute recorder address
        bytes32 recorderSalt = keccak256(abi.encodePacked("recorder", key));
        bytes memory recorderBytecode =
            abi.encodePacked(type(EscrowPeriodRecorder).creationCode, abi.encode(escrowPeriod, freezePolicy));
        bytes32 recorderHash =
            keccak256(abi.encodePacked(bytes1(0xff), address(this), recorderSalt, keccak256(recorderBytecode)));
        recorder = address(uint160(uint256(recorderHash)));

        // Compute condition address
        bytes32 conditionSalt = keccak256(abi.encodePacked("condition", key));
        bytes memory conditionBytecode =
            abi.encodePacked(type(EscrowPeriodCondition).creationCode, abi.encode(recorder));
        bytes32 conditionHash =
            keccak256(abi.encodePacked(bytes1(0xff), address(this), conditionSalt, keccak256(conditionBytecode)));
        condition = address(uint160(uint256(conditionHash)));
    }

    /**
     * @notice Get the key for a configuration
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract
     * @return The mapping key
     */
    function getKey(uint256 escrowPeriod, address freezePolicy) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(escrowPeriod, freezePolicy));
    }
}
