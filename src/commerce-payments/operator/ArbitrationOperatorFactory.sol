// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {ArbitrationOperator} from "./ArbitrationOperator.sol";

/**
 * @title ArbitrationOperatorFactory
 * @notice Factory contract that deploys ArbitrationOperator instances
 *         for unique arbiter configurations.
 *
 * @dev Design rationale:
 *      - Each unique arbiter gets its own operator contract
 *      - The operator address encodes the arbiter
 *      - Client signs ERC-3009 with operator in PaymentInfo, committing to the arbiter
 *      - Refund delay is per-payment via refundExpiry in PaymentInfo (signed by payer)
 *      - No custom nonce computation or second signature needed
 *      - Works with Base Commerce Payments as designed
 */
contract ArbitrationOperatorFactory {
    // Immutable configuration shared by all deployed operators
    address public immutable ESCROW;
    address public immutable PROTOCOL_FEE_RECIPIENT;
    uint256 public immutable MAX_TOTAL_FEE_RATE;
    uint256 public immutable PROTOCOL_FEE_PERCENTAGE;

    // arbiter => operator address
    mapping(address => address) public operators;

    // Events
    event OperatorDeployed(
        address indexed operator,
        address indexed arbiter
    );

    // Custom errors
    error ZeroAddress();
    error ZeroAmount();

    constructor(
        address _escrow,
        address _protocolFeeRecipient,
        uint256 _maxTotalFeeRate,
        uint256 _protocolFeePercentage
    ) {
        if (_escrow == address(0)) revert ZeroAddress();
        if (_protocolFeeRecipient == address(0)) revert ZeroAddress();
        if (_maxTotalFeeRate == 0) revert ZeroAmount();

        ESCROW = _escrow;
        PROTOCOL_FEE_RECIPIENT = _protocolFeeRecipient;
        MAX_TOTAL_FEE_RATE = _maxTotalFeeRate;
        PROTOCOL_FEE_PERCENTAGE = _protocolFeePercentage;
    }

    /**
     * @notice Get the operator address for a given arbiter
     * @param arbiter The arbiter address
     * @return operator The operator address (address(0) if not deployed)
     */
    function getOperator(address arbiter) external view returns (address) {
        return operators[arbiter];
    }

    /**
     * @notice Deploy an operator for a given arbiter
     * @dev Idempotent - returns existing operator if already deployed
     * @param arbiter The arbiter address
     * @param owner The owner address for the deployed operator (controls fee settings)
     * @return operator The operator address
     */
    function deployOperator(address arbiter, address owner) external returns (address operator) {
        if (arbiter == address(0)) revert ZeroAddress();
        if (owner == address(0)) revert ZeroAddress();

        // Return existing if already deployed (idempotent)
        if (operators[arbiter] != address(0)) {
            return operators[arbiter];
        }

        // Deploy new operator with this arbiter baked in
        operator = address(new ArbitrationOperator(
            ESCROW,
            PROTOCOL_FEE_RECIPIENT,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            arbiter,
            owner
        ));

        operators[arbiter] = operator;

        emit OperatorDeployed(operator, arbiter);

        return operator;
    }
}
