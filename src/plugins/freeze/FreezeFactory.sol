// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {Freeze} from "./Freeze.sol";
import {FreezeDeployed} from "./types/Events.sol";
import {ZeroAddress} from "../../types/Errors.sol";

/**
 * @title FreezeFactory
 * @notice Factory for deploying Freeze condition contracts with deterministic addresses.
 *         Uses CREATE2 for address predictability.
 *
 * @dev Deployment flow:
 *      1. Deploy Freeze with (freezePolicy, escrowPeriodContract, escrow)
 *      2. Return address
 *
 *      The key for looking up deployments is keccak256(freezePolicy, escrowPeriodContract).
 *      ESCROW is factory-level (immutable), not per-config.
 */
contract FreezeFactory {
    /// @notice Escrow contract shared by all deployments
    AuthCaptureEscrow public immutable ESCROW;

    constructor(address escrow) {
        if (escrow == address(0)) revert ZeroAddress();
        ESCROW = AuthCaptureEscrow(escrow);
    }

    /// @notice Deployed Freeze addresses
    /// @dev Key: keccak256(abi.encodePacked(freezePolicy, escrowPeriodContract))
    mapping(bytes32 => address) public deployments;

    /**
     * @notice Deploy a new Freeze condition contract
     * @param freezePolicy Address of the freeze policy contract (required)
     * @param escrowPeriodContract Address of the EscrowPeriod contract (address(0) = unconstrained)
     * @return freezeAddr Address of the deployed Freeze contract
     */
    function deploy(address freezePolicy, address escrowPeriodContract) external returns (address freezeAddr) {
        bytes32 key = getKey(freezePolicy, escrowPeriodContract);

        // Return existing deployment if already deployed
        if (deployments[key] != address(0)) {
            return deployments[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("freeze", key));
        bytes memory bytecode = abi.encodePacked(
            type(Freeze).creationCode, abi.encode(freezePolicy, escrowPeriodContract, address(ESCROW))
        );
        freezeAddr = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        deployments[key] = freezeAddr;

        emit FreezeDeployed(freezeAddr, freezePolicy, escrowPeriodContract);

        // ============ INTERACTIONS ============
        address deployed = address(new Freeze{salt: salt}(freezePolicy, escrowPeriodContract, address(ESCROW)));

        assert(deployed == freezeAddr);
    }

    /**
     * @notice Get deployed address for a configuration
     * @param freezePolicy Address of the freeze policy contract
     * @param escrowPeriodContract Address of the EscrowPeriod contract
     * @return Address of the deployed Freeze contract (address(0) if not deployed)
     */
    function getDeployed(address freezePolicy, address escrowPeriodContract) external view returns (address) {
        return deployments[getKey(freezePolicy, escrowPeriodContract)];
    }

    /**
     * @notice Compute the deterministic address for a configuration (before deployment)
     * @param freezePolicy Address of the freeze policy contract
     * @param escrowPeriodContract Address of the EscrowPeriod contract
     * @return Predicted address of the Freeze contract
     */
    function computeAddress(address freezePolicy, address escrowPeriodContract) external view returns (address) {
        bytes32 key = getKey(freezePolicy, escrowPeriodContract);
        bytes32 salt = keccak256(abi.encodePacked("freeze", key));
        bytes memory bytecode = abi.encodePacked(
            type(Freeze).creationCode, abi.encode(freezePolicy, escrowPeriodContract, address(ESCROW))
        );
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a configuration
     * @param freezePolicy Address of the freeze policy contract
     * @param escrowPeriodContract Address of the EscrowPeriod contract
     * @return The mapping key
     */
    function getKey(address freezePolicy, address escrowPeriodContract) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(freezePolicy, escrowPeriodContract));
    }
}
