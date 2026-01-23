// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {EscrowPeriodCondition} from "./EscrowPeriodCondition.sol";
import {InvalidEscrowPeriod} from "./types/Errors.sol";
import {EscrowPeriodConditionDeployed} from "./types/Events.sol";

/**
 * @title EscrowPeriodConditionFactory
 * @notice Factory contract that deploys EscrowPeriodCondition instances.
 *         Each unique (escrowPeriod, freezePolicy) pair gets its own condition contract.
 *
 * @dev Design rationale:
 *      - Conditions are keyed by (escrowPeriod, freezePolicy)
 *      - Same condition can be reused across multiple operators
 *      - Idempotent deployment - returns existing if already deployed
 */
contract EscrowPeriodConditionFactory {
    // keccak256(escrowPeriod, freezePolicy) => condition address
    mapping(bytes32 => address) public conditions;

    /**
     * @notice Get the condition address for a given escrow period and freeze policy
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract (or address(0) for none)
     * @return condition The condition address (address(0) if not deployed)
     */
    function getCondition(uint256 escrowPeriod, address freezePolicy) external view returns (address) {
        bytes32 key = keccak256(abi.encode(escrowPeriod, freezePolicy));
        return conditions[key];
    }

    /**
     * @notice Get the condition address for a given escrow period (no freeze policy)
     * @dev Convenience function for backward compatibility
     * @param escrowPeriod Duration of the escrow period in seconds
     * @return condition The condition address (address(0) if not deployed)
     */
    function getCondition(uint256 escrowPeriod) external view returns (address) {
        bytes32 key = keccak256(abi.encode(escrowPeriod, address(0)));
        return conditions[key];
    }

    /**
     * @notice Calculate the deterministic address for an escrow condition
     * @dev Uses CREATE2 formula: keccak256(0xff ++ address(this) ++ salt ++ keccak256(bytecode))
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract (or address(0) for none)
     * @return condition The predicted condition address
     */
    function computeAddress(uint256 escrowPeriod, address freezePolicy) external view returns (address condition) {
        bytes32 salt = keccak256(abi.encode(escrowPeriod, freezePolicy));

        bytes memory bytecode = abi.encodePacked(
            type(EscrowPeriodCondition).creationCode,
            abi.encode(escrowPeriod, freezePolicy)
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
     * @notice Calculate the deterministic address for an escrow condition (no freeze policy)
     * @dev Convenience function for backward compatibility
     * @param escrowPeriod Duration of the escrow period in seconds
     * @return condition The predicted condition address
     */
    function computeAddress(uint256 escrowPeriod) external view returns (address condition) {
        return this.computeAddress(escrowPeriod, address(0));
    }

    /**
     * @notice Deploy an escrow period condition
     * @dev Idempotent - returns existing condition if already deployed.
     *      Uses CREATE2 for deterministic addresses.
     * @param escrowPeriod Duration of the escrow period in seconds
     * @param freezePolicy Address of the freeze policy contract (or address(0) for none)
     * @return condition The condition address
     */
    function deployCondition(uint256 escrowPeriod, address freezePolicy) external returns (address condition) {
        if (escrowPeriod == 0) revert InvalidEscrowPeriod();

        bytes32 key = keccak256(abi.encode(escrowPeriod, freezePolicy));

        // Return existing if already deployed (idempotent)
        if (conditions[key] != address(0)) {
            return conditions[key];
        }

        // Deploy new condition using CREATE2
        bytes32 salt = key;

        condition = address(new EscrowPeriodCondition{salt: salt}(escrowPeriod, freezePolicy));

        conditions[key] = condition;

        emit EscrowPeriodConditionDeployed(condition, escrowPeriod);

        return condition;
    }

    /**
     * @notice Deploy an escrow period condition (no freeze policy)
     * @dev Convenience function for backward compatibility
     * @param escrowPeriod Duration of the escrow period in seconds
     * @return condition The condition address
     */
    function deployCondition(uint256 escrowPeriod) external returns (address condition) {
        return this.deployCondition(escrowPeriod, address(0));
    }
}
