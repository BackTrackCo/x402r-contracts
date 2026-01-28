// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {EscrowPeriod} from "./EscrowPeriod.sol";
import {EscrowPeriodDeployed} from "./types/Events.sol";
import {ZeroAddress} from "../../types/Errors.sol";

/**
 * @title EscrowPeriodFactory
 * @notice Factory for deploying EscrowPeriod contracts with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Deployment flow:
 *      1. Deploy EscrowPeriod with (escrowPeriod, freezePolicy, escrow, authorizedCodehash)
 *      2. Return address (single contract replaces old recorder+condition pair)
 *
 *      The key for looking up deployments is keccak256(escrowPeriod, freezePolicy, authorizedCodehash).
 *      ESCROW is factory-level (immutable), not per-config.
 */
contract EscrowPeriodFactory {
    /// @notice Escrow contract shared by all deployments
    AuthCaptureEscrow public immutable ESCROW;

    constructor(address escrow) {
        if (escrow == address(0)) revert ZeroAddress();
        ESCROW = AuthCaptureEscrow(escrow);
    }

    /// @notice Deployed EscrowPeriod addresses
    /// @dev Key: keccak256(abi.encodePacked(escrowPeriod, freezePolicy, authorizedCodehash))
    mapping(bytes32 => address) public deployments;

    /**
     * @notice Deploy a new EscrowPeriod contract
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract (address(0) = no freeze)
     * @param authorizedCodehash Runtime codehash of authorized caller (bytes32(0) = operator-only)
     * @return escrowPeriodAddr Address of the deployed EscrowPeriod contract
     */
    function deploy(uint256 escrowPeriod, address freezePolicy, bytes32 authorizedCodehash)
        external
        returns (address escrowPeriodAddr)
    {
        bytes32 key = getKey(escrowPeriod, freezePolicy, authorizedCodehash);

        // Return existing deployment if already deployed
        if (deployments[key] != address(0)) {
            return deployments[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("escrowPeriod", key));
        bytes memory bytecode = abi.encodePacked(
            type(EscrowPeriod).creationCode, abi.encode(escrowPeriod, freezePolicy, address(ESCROW), authorizedCodehash)
        );
        escrowPeriodAddr = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        deployments[key] = escrowPeriodAddr;

        emit EscrowPeriodDeployed(escrowPeriodAddr, escrowPeriod);

        // ============ INTERACTIONS ============
        address deployed =
            address(new EscrowPeriod{salt: salt}(escrowPeriod, freezePolicy, address(ESCROW), authorizedCodehash));

        assert(deployed == escrowPeriodAddr);
    }

    /**
     * @notice Get deployed address for a configuration
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract
     * @param authorizedCodehash Runtime codehash of authorized caller (bytes32(0) = operator-only)
     * @return Address of the deployed EscrowPeriod (address(0) if not deployed)
     */
    function getDeployed(uint256 escrowPeriod, address freezePolicy, bytes32 authorizedCodehash)
        external
        view
        returns (address)
    {
        return deployments[getKey(escrowPeriod, freezePolicy, authorizedCodehash)];
    }

    /**
     * @notice Compute the deterministic address for a configuration (before deployment)
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract
     * @param authorizedCodehash Runtime codehash of authorized caller (bytes32(0) = operator-only)
     * @return Predicted address of the EscrowPeriod contract
     */
    function computeAddress(uint256 escrowPeriod, address freezePolicy, bytes32 authorizedCodehash)
        external
        view
        returns (address)
    {
        bytes32 key = getKey(escrowPeriod, freezePolicy, authorizedCodehash);
        bytes32 salt = keccak256(abi.encodePacked("escrowPeriod", key));
        bytes memory bytecode = abi.encodePacked(
            type(EscrowPeriod).creationCode, abi.encode(escrowPeriod, freezePolicy, address(ESCROW), authorizedCodehash)
        );
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
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
