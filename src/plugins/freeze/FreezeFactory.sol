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
 *      1. Deploy Freeze with (freezeCondition, unfreezeCondition, freezeDuration, escrowPeriodContract, escrow)
 *      2. Return address
 *
 *      The key for looking up deployments is keccak256(freezeCondition, unfreezeCondition, freezeDuration, escrowPeriodContract).
 *      ESCROW is factory-level (immutable), not per-config.
 *
 *      Example configurations:
 *      - Payer freeze/unfreeze (3 days): deploy(PayerCondition, PayerCondition, 3 days, escrowPeriod)
 *      - Payer freeze, Arbiter unfreeze: deploy(PayerCondition, StaticAddressCondition, 0, escrowPeriod)
 *      - Anyone freeze, Receiver unfreeze: deploy(AlwaysTrueCondition, ReceiverCondition, 7 days, escrowPeriod)
 */
contract FreezeFactory {
    /// @notice Escrow contract shared by all deployments
    AuthCaptureEscrow public immutable ESCROW;

    constructor(address escrow) {
        if (escrow == address(0)) revert ZeroAddress();
        ESCROW = AuthCaptureEscrow(escrow);
    }

    /// @notice Deployed Freeze addresses
    /// @dev Key: keccak256(abi.encodePacked(freezeCondition, unfreezeCondition, freezeDuration, escrowPeriodContract))
    mapping(bytes32 => address) public deployments;

    /**
     * @notice Deploy a new Freeze condition contract
     * @param freezeCondition ICondition that authorizes freeze calls (required)
     * @param unfreezeCondition ICondition that authorizes unfreeze calls (required)
     * @param freezeDuration Duration that freezes last (0 = permanent until unfrozen)
     * @param escrowPeriodContract Address of the EscrowPeriod contract (address(0) = unconstrained)
     * @return freezeAddr Address of the deployed Freeze contract
     * @custom:security RACE CONDITION: When the deployed Freeze is composed with EscrowPeriod via
     *         AndCondition, a race exists at the escrow period boundary — freeze() reverts
     *         (FreezeWindowExpired) at the exact moment release becomes possible. Deploy with
     *         sufficient FREEZE_DURATION margin relative to ESCROW_PERIOD to mitigate.
     */
    function deploy(
        address freezeCondition,
        address unfreezeCondition,
        uint256 freezeDuration,
        address escrowPeriodContract
    ) external returns (address freezeAddr) {
        bytes32 key = getKey(freezeCondition, unfreezeCondition, freezeDuration, escrowPeriodContract);

        // Return existing deployment if already deployed
        if (deployments[key] != address(0)) {
            return deployments[key];
        }

        // ============ EFFECTS ============
        // Pre-compute deterministic CREATE2 address (CEI pattern)
        bytes32 salt = keccak256(abi.encodePacked("freeze", key));
        bytes memory bytecode = abi.encodePacked(
            type(Freeze).creationCode,
            abi.encode(freezeCondition, unfreezeCondition, freezeDuration, escrowPeriodContract, address(ESCROW))
        );
        freezeAddr = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)))))
        );

        // Store address before deployment
        deployments[key] = freezeAddr;

        emit FreezeDeployed(freezeAddr, freezeCondition, unfreezeCondition, freezeDuration, escrowPeriodContract);

        // ============ INTERACTIONS ============
        address deployed = address(
            new Freeze{salt: salt}(
                freezeCondition, unfreezeCondition, freezeDuration, escrowPeriodContract, address(ESCROW)
            )
        );

        assert(deployed == freezeAddr);
    }

    /**
     * @notice Get deployed address for a configuration
     * @param freezeCondition ICondition that authorizes freeze calls
     * @param unfreezeCondition ICondition that authorizes unfreeze calls
     * @param freezeDuration Duration that freezes last
     * @param escrowPeriodContract Address of the EscrowPeriod contract
     * @return Address of the deployed Freeze contract (address(0) if not deployed)
     */
    function getDeployed(
        address freezeCondition,
        address unfreezeCondition,
        uint256 freezeDuration,
        address escrowPeriodContract
    ) external view returns (address) {
        return deployments[getKey(freezeCondition, unfreezeCondition, freezeDuration, escrowPeriodContract)];
    }

    /**
     * @notice Compute the deterministic address for a configuration (before deployment)
     * @param freezeCondition ICondition that authorizes freeze calls
     * @param unfreezeCondition ICondition that authorizes unfreeze calls
     * @param freezeDuration Duration that freezes last
     * @param escrowPeriodContract Address of the EscrowPeriod contract
     * @return Predicted address of the Freeze contract
     */
    function computeAddress(
        address freezeCondition,
        address unfreezeCondition,
        uint256 freezeDuration,
        address escrowPeriodContract
    ) external view returns (address) {
        bytes32 key = getKey(freezeCondition, unfreezeCondition, freezeDuration, escrowPeriodContract);
        bytes32 salt = keccak256(abi.encodePacked("freeze", key));
        bytes memory bytecode = abi.encodePacked(
            type(Freeze).creationCode,
            abi.encode(freezeCondition, unfreezeCondition, freezeDuration, escrowPeriodContract, address(ESCROW))
        );
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Get the key for a configuration
     * @param freezeCondition ICondition that authorizes freeze calls
     * @param unfreezeCondition ICondition that authorizes unfreeze calls
     * @param freezeDuration Duration that freezes last
     * @param escrowPeriodContract Address of the EscrowPeriod contract
     * @return The mapping key
     */
    function getKey(
        address freezeCondition,
        address unfreezeCondition,
        uint256 freezeDuration,
        address escrowPeriodContract
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(freezeCondition, unfreezeCondition, freezeDuration, escrowPeriodContract));
    }
}
