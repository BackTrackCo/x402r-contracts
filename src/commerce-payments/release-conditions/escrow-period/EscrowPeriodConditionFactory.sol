// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {EscrowPeriodCondition} from "./EscrowPeriodCondition.sol";
import {InvalidEscrowPeriod} from "./types/Errors.sol";
import {EscrowPeriodConditionDeployed} from "./types/Events.sol";

/**
 * @title EscrowPeriodConditionFactory
 * @notice Factory contract that deploys EscrowPeriodCondition instances.
 *         Each unique (escrowPeriod, freezePolicy, canBypass, noteBypass) tuple gets its own condition contract.
 *
 * @dev Design rationale:
 *      - Conditions are keyed by (escrowPeriod, freezePolicy, canBypass, noteBypass)
 *      - Same condition can be reused across multiple operators
 *      - Idempotent deployment - returns existing if already deployed
 *      - canBypass is typically PayerOnly for payer bypass in can() checks
 *      - noteBypass is typically PayerOnly for payer bypass in note() calls
 */
contract EscrowPeriodConditionFactory {
    // keccak256(escrowPeriod, freezePolicy, canBypass, noteBypass) => condition address
    mapping(bytes32 => address) public conditions;

    /**
     * @notice Get the condition address for a given configuration
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract (or address(0) for none)
     * @param canBypass Address of the bypass condition for payer in can() checks (e.g., PayerOnly)
     * @param noteBypass Address of the bypass condition for payer in note() calls (e.g., PayerOnly)
     * @return condition The condition address (address(0) if not deployed)
     */
    function getCondition(uint256 escrowPeriod, address freezePolicy, address canBypass, address noteBypass) external view returns (address) {
        bytes32 key = keccak256(abi.encode(escrowPeriod, freezePolicy, canBypass, noteBypass));
        return conditions[key];
    }

    /**
     * @notice Calculate the deterministic address for an escrow condition
     * @dev Uses CREATE2 formula: keccak256(0xff ++ address(this) ++ salt ++ keccak256(bytecode))
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract (or address(0) for none)
     * @param canBypass Address of the bypass condition for payer in can() checks
     * @param noteBypass Address of the bypass condition for payer in note() calls
     * @return condition The predicted condition address
     */
    function computeAddress(uint256 escrowPeriod, address freezePolicy, address canBypass, address noteBypass) external view returns (address condition) {
        bytes32 salt = keccak256(abi.encode(escrowPeriod, freezePolicy, canBypass, noteBypass));

        bytes memory bytecode = abi.encodePacked(
            type(EscrowPeriodCondition).creationCode,
            abi.encode(escrowPeriod, freezePolicy, canBypass, noteBypass)
        );

        bytes32 bytecodeHash = keccak256(bytecode);

        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            bytecodeHash
        )))));
    }

    /**
     * @notice Deploy an escrow period condition
     * @dev Idempotent - returns existing condition if already deployed.
     *      Uses CREATE2 for deterministic addresses.
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract (or address(0) for none)
     * @param canBypass Address of the bypass condition for payer in can() checks (e.g., PayerOnly)
     * @param noteBypass Address of the bypass condition for payer in note() calls (e.g., PayerOnly)
     * @return condition The condition address
     */
    function deployCondition(uint256 escrowPeriod, address freezePolicy, address canBypass, address noteBypass) external returns (address condition) {
        // ============ CHECKS ============
        if (escrowPeriod == 0) revert InvalidEscrowPeriod();

        bytes32 key = keccak256(abi.encode(escrowPeriod, freezePolicy, canBypass, noteBypass));

        // Return existing if already deployed (idempotent)
        if (conditions[key] != address(0)) {
            return conditions[key];
        }

        // ============ EFFECTS ============
        // Compute deterministic CREATE2 address before deployment (CEI pattern)
        bytes memory bytecode = abi.encodePacked(
            type(EscrowPeriodCondition).creationCode,
            abi.encode(escrowPeriod, freezePolicy, canBypass, noteBypass)
        );
        condition = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            key,
            keccak256(bytecode)
        )))));

        // Store before external interaction
        conditions[key] = condition;

        emit EscrowPeriodConditionDeployed(condition, escrowPeriod);

        // ============ INTERACTIONS ============
        // Deploy new condition using CREATE2 - address is deterministic
        address deployed = address(new EscrowPeriodCondition{salt: key}(escrowPeriod, freezePolicy, canBypass, noteBypass));

        // Sanity check - CREATE2 address must match
        assert(deployed == condition);

        return condition;
    }
}
