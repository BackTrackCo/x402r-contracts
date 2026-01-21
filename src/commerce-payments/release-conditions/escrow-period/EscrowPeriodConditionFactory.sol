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
     * @notice Deploy an escrow period condition for a given period
     * @dev Idempotent - returns existing condition if already deployed.
     * @param escrowPeriod Duration of the escrow period in seconds
     * @return condition The condition address
     */
    function deployCondition(uint256 escrowPeriod) external returns (address condition) {
        if (escrowPeriod == 0) revert InvalidEscrowPeriod();

        // Return existing if already deployed (idempotent)
        if (conditions[escrowPeriod] != address(0)) {
            return conditions[escrowPeriod];
        }

        // Deploy new condition
        condition = address(new EscrowPeriodCondition(escrowPeriod));

        conditions[escrowPeriod] = condition;

        emit EscrowPeriodConditionDeployed(condition, escrowPeriod);

        return condition;
    }
}
