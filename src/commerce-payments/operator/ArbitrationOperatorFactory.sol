// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {Ownable} from "solady/auth/Ownable.sol";
import {ArbitrationOperator} from "./arbitration/ArbitrationOperator.sol";
import {ZeroAddress, ZeroAmount} from "../types/Errors.sol";
import {ZeroEscrowPeriod} from "./types/Errors.sol";
import {OperatorDeployed} from "./types/Events.sol";

/**
 * @title ArbitrationOperatorFactory
 * @notice Factory contract that deploys ArbitrationOperator instances
 *         for unique arbiter + escrow period configurations.
 *
 * @dev Design rationale:
 *      - Each unique (arbiter, escrowPeriod) pair gets its own operator contract
 *      - The operator address encodes both the arbiter and escrow period
 *      - Client signs ERC-3009 with operator in PaymentInfo, committing to arbiter and escrow terms
 *      - Factory owner controls fee settings on all deployed operators
 *      - No custom nonce computation or second signature needed
 *      - Works with Base Commerce Payments as designed
 */
contract ArbitrationOperatorFactory is Ownable {
    // Immutable configuration shared by all deployed operators
    address public immutable ESCROW;
    address public immutable PROTOCOL_FEE_RECIPIENT;
    uint256 public immutable MAX_TOTAL_FEE_RATE;
    uint256 public immutable PROTOCOL_FEE_PERCENTAGE;

    // keccak256(arbiter, escrowPeriod) => operator address
    mapping(bytes32 => address) public operators;

    constructor(
        address _escrow,
        address _protocolFeeRecipient,
        uint256 _maxTotalFeeRate,
        uint256 _protocolFeePercentage,
        address _owner
    ) {
        if (_escrow == address(0)) revert ZeroAddress();
        if (_protocolFeeRecipient == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        if (_maxTotalFeeRate == 0) revert ZeroAmount();
        _initializeOwner(_owner);

        ESCROW = _escrow;
        PROTOCOL_FEE_RECIPIENT = _protocolFeeRecipient;
        MAX_TOTAL_FEE_RATE = _maxTotalFeeRate;
        PROTOCOL_FEE_PERCENTAGE = _protocolFeePercentage;
    }

    /**
     * @notice Get the operator address for a given arbiter and escrow period
     * @param arbiter The arbiter address
     * @param escrowPeriod The escrow period in seconds
     * @return operator The operator address (address(0) if not deployed)
     */
    function getOperator(address arbiter, uint48 escrowPeriod) external view returns (address) {
        bytes32 key = keccak256(abi.encodePacked(arbiter, escrowPeriod));
        return operators[key];
    }

    /**
     * @notice Deploy an operator for a given arbiter and escrow period
     * @dev Idempotent - returns existing operator if already deployed.
     *      Factory owner becomes the operator owner (controls fee settings).
     * @param arbiter The arbiter address
     * @param escrowPeriod The escrow period in seconds (time before merchant can capture)
     * @return operator The operator address
     */
    function deployOperator(address arbiter, uint48 escrowPeriod) external returns (address operator) {
        if (arbiter == address(0)) revert ZeroAddress();
        if (escrowPeriod == 0) revert ZeroEscrowPeriod();

        bytes32 key = keccak256(abi.encodePacked(arbiter, escrowPeriod));

        // Return existing if already deployed (idempotent)
        if (operators[key] != address(0)) {
            return operators[key];
        }

        // Deploy new operator with arbiter and escrow period baked in
        // Factory owner becomes operator owner (controls fee settings)
        operator = address(new ArbitrationOperator(
            ESCROW,
            PROTOCOL_FEE_RECIPIENT,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            arbiter,
            owner(),
            escrowPeriod
        ));

        operators[key] = operator;

        emit OperatorDeployed(operator, arbiter, escrowPeriod);

        return operator;
    }
}
