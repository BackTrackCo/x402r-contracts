// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {EscrowPeriodCondition} from "./EscrowPeriodCondition.sol";
import {InvalidEscrowPeriod} from "./types/Errors.sol";
import {EscrowPeriodConditionDeployed} from "./types/Events.sol";

/**
 * @title EscrowPeriodConditionFactory
 * @notice Factory contract that deploys EscrowPeriodCondition instances.
 *         Each unique escrowPeriod gets its own condition contract.
 *
 * @dev Design rationale:
 *      - Conditions are keyed only by escrowPeriod
 *      - Same condition can be reused across multiple operators
 *      - Idempotent deployment - returns existing if already deployed
 */
contract EscrowPeriodConditionFactory {
    // escrowPeriod => condition address
    mapping(uint256 => address) public conditions;

    /**
     * @notice Get the condition address for a given escrow period
     * @param escrowPeriod Duration of the escrow period in seconds
     * @return condition The condition address (address(0) if not deployed)
     */
    function getCondition(uint256 escrowPeriod) external view returns (address) {
        return conditions[escrowPeriod];
    }

    /**
     * @notice Calculate the deterministic address for an escrow condition
     * @dev Uses CREATE2 formula: keccak256(0xff ++ address(this) ++ salt ++ keccak256(bytecode))
     * @param escrowPeriod Duration of the escrow period in seconds
     * @return condition The predicted condition address
     */
    function computeAddress(uint256 escrowPeriod) external view returns (address condition) {
        bytes32 salt = bytes32(escrowPeriod);
        
        bytes memory bytecode = abi.encodePacked(
            type(EscrowPeriodCondition).creationCode,
            abi.encode(escrowPeriod)
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
     * @notice Deploy an escrow period condition for a given period
     * @dev Idempotent - returns existing condition if already deployed.
     *      Uses CREATE2 for deterministic addresses.
     * @param escrowPeriod Duration of the escrow period in seconds
     * @return condition The condition address
     */
    function deployCondition(uint256 escrowPeriod) external returns (address condition) {
        if (escrowPeriod == 0) revert InvalidEscrowPeriod();

        // Return existing if already deployed (idempotent)
        if (conditions[escrowPeriod] != address(0)) {
            return conditions[escrowPeriod];
        }

        // Deploy new condition using CREATE2
        // Salt is simply the escrowPeriod directly (as bytes32)
        bytes32 salt = bytes32(escrowPeriod);
        
        condition = address(new EscrowPeriodCondition{salt: salt}(escrowPeriod));

        conditions[escrowPeriod] = condition;

        emit EscrowPeriodConditionDeployed(condition, escrowPeriod);

        return condition;
    }
}
