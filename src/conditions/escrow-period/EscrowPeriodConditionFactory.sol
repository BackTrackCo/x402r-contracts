// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {EscrowPeriodRecorder} from "./EscrowPeriodRecorder.sol";
import {EscrowPeriodCondition} from "./EscrowPeriodCondition.sol";
import {EscrowPeriodConditionDeployed} from "./types/Events.sol";
import {ZeroAddress} from "../../types/Errors.sol";

/**
 * @title EscrowPeriodConditionFactory
 * @notice Factory for deploying EscrowPeriodRecorder and EscrowPeriodCondition pairs.
 *         Uses CREATE2 for deterministic addresses.
 *
 * @dev Deployment flow:
 *      1. Deploy recorder with (escrowPeriod, freezePolicy, escrow, authorizedCodehash)
 *      2. Deploy condition pointing to the recorder
 *      3. Return both addresses
 *
 *      The key for looking up deployed pairs is keccak256(escrowPeriod, freezePolicy, authorizedCodehash).
 *      ESCROW is factory-level (immutable), not per-config.
 */
contract EscrowPeriodConditionFactory {
    /// @notice Escrow contract shared by all deployments
    AuthCaptureEscrow public immutable ESCROW;

    constructor(address escrow) {
        if (escrow == address(0)) revert ZeroAddress();
        ESCROW = AuthCaptureEscrow(escrow);
    }

    /// @notice Deployed recorder addresses
    /// @dev Key: keccak256(abi.encodePacked(escrowPeriod, freezePolicy, authorizedCodehash))
    mapping(bytes32 => address) public recorders;

    /// @notice Deployed condition addresses
    /// @dev Key: keccak256(abi.encodePacked(escrowPeriod, freezePolicy, authorizedCodehash))
    mapping(bytes32 => address) public conditions;

    /**
     * @notice Deploy a new EscrowPeriodRecorder and EscrowPeriodCondition pair
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract (address(0) = no freeze)
     * @param authorizedCodehash Runtime codehash of authorized caller (bytes32(0) = operator-only)
     * @return recorder Address of the deployed recorder
     * @return condition Address of the deployed condition
     */
    function deploy(uint256 escrowPeriod, address freezePolicy, bytes32 authorizedCodehash)
        external
        returns (address recorder, address condition)
    {
        bytes32 key = getKey(escrowPeriod, freezePolicy, authorizedCodehash);

        // Return existing deployment if already deployed
        if (recorders[key] != address(0)) {
            return (recorders[key], conditions[key]);
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 addresses (CEI pattern)
        bytes32 recorderSalt = keccak256(abi.encodePacked("recorder", key));
        bytes memory recorderBytecode = abi.encodePacked(
            type(EscrowPeriodRecorder).creationCode,
            abi.encode(escrowPeriod, freezePolicy, address(ESCROW), authorizedCodehash)
        );
        recorder = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), recorderSalt, keccak256(recorderBytecode)))
                )
            )
        );

        bytes32 conditionSalt = keccak256(abi.encodePacked("condition", key));
        bytes memory conditionBytecode =
            abi.encodePacked(type(EscrowPeriodCondition).creationCode, abi.encode(recorder));
        condition = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), conditionSalt, keccak256(conditionBytecode))
                    )
                )
            )
        );

        // Store addresses before deployment
        recorders[key] = recorder;
        conditions[key] = condition;

        emit EscrowPeriodConditionDeployed(condition, recorder, escrowPeriod);

        // ============ INTERACTIONS ============
        address deployedRecorder = address(
            new EscrowPeriodRecorder{salt: recorderSalt}(
                escrowPeriod, freezePolicy, address(ESCROW), authorizedCodehash
            )
        );
        address deployedCondition = address(new EscrowPeriodCondition{salt: conditionSalt}(recorder));

        assert(deployedRecorder == recorder);
        assert(deployedCondition == condition);
    }

    /**
     * @notice Get deployed addresses for a configuration
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract
     * @param authorizedCodehash Runtime codehash of authorized caller (bytes32(0) = operator-only)
     * @return recorder Address of the deployed recorder (address(0) if not deployed)
     * @return condition Address of the deployed condition (address(0) if not deployed)
     */
    function getDeployed(uint256 escrowPeriod, address freezePolicy, bytes32 authorizedCodehash)
        external
        view
        returns (address recorder, address condition)
    {
        bytes32 key = getKey(escrowPeriod, freezePolicy, authorizedCodehash);
        return (recorders[key], conditions[key]);
    }

    /**
     * @notice Compute the deterministic addresses for a configuration (before deployment)
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract
     * @param authorizedCodehash Runtime codehash of authorized caller (bytes32(0) = operator-only)
     * @return recorder Predicted address of the recorder
     * @return condition Predicted address of the condition
     */
    function computeAddresses(uint256 escrowPeriod, address freezePolicy, bytes32 authorizedCodehash)
        external
        view
        returns (address recorder, address condition)
    {
        bytes32 key = getKey(escrowPeriod, freezePolicy, authorizedCodehash);

        // Compute recorder address
        bytes32 recorderSalt = keccak256(abi.encodePacked("recorder", key));
        bytes memory recorderBytecode = abi.encodePacked(
            type(EscrowPeriodRecorder).creationCode,
            abi.encode(escrowPeriod, freezePolicy, address(ESCROW), authorizedCodehash)
        );
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
     * @param authorizedCodehash Runtime codehash of authorized caller (bytes32(0) = operator-only)
     * @return The mapping key
     */
    function getKey(uint256 escrowPeriod, address freezePolicy, bytes32 authorizedCodehash)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(escrowPeriod, freezePolicy, authorizedCodehash));
    }
}
