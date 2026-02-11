// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {PaymentOperator} from "./payment/PaymentOperator.sol";
import {ZeroAddress} from "../types/Errors.sol";
import {OperatorDeployed} from "./types/Events.sol";

/**
 * @title PaymentOperatorFactory
 * @notice Factory contract that deploys PaymentOperator instances with pluggable conditions.
 *         Each unique configuration gets its own operator contract.
 *
 * @dev Condition Combinator Architecture:
 *      - Operators have 10 slots: 5 conditions (before checks) + 5 recorders (after state updates)
 *      - address(0) = default behavior (allow for conditions, no-op for recorders)
 *      - Conditions implement ICondition.check() -> returns bool (true = allowed)
 *      - Recorders implement IRecorder.record() -> updates state after action
 *      - Conditions can be composed using combinators (Or, And, Not)
 *      - Client signs ERC-3009 with operator in PaymentInfo, committing to all conditions
 *      - Factory deploys deterministic operator instances via CREATE2
 *      - Works with Base Commerce Payments as designed
 *
 */
contract PaymentOperatorFactory {
    /// @notice Configuration struct for deploying operators
    struct OperatorConfig {
        address feeRecipient;
        address feeCalculator;
        address authorizeCondition;
        address authorizeRecorder;
        address chargeCondition;
        address chargeRecorder;
        address releaseCondition;
        address releaseRecorder;
        address refundInEscrowCondition;
        address refundInEscrowRecorder;
        address refundPostEscrowCondition;
        address refundPostEscrowRecorder;
    }

    // Immutable configuration shared by all deployed operators
    address public immutable ESCROW;
    address public immutable PROTOCOL_FEE_CONFIG;

    // keccak256(config) => operator address
    mapping(bytes32 => address) public operators;

    constructor(address _escrow, address _protocolFeeConfig) {
        if (_escrow == address(0)) revert ZeroAddress();
        if (_protocolFeeConfig == address(0)) revert ZeroAddress();

        ESCROW = _escrow;
        PROTOCOL_FEE_CONFIG = _protocolFeeConfig;
    }

    /**
     * @notice Get the operator address for a given configuration
     * @param config The operator configuration
     * @return operator The operator address (address(0) if not deployed)
     */
    function getOperator(OperatorConfig calldata config) external view returns (address) {
        bytes32 key = _computeKey(config);
        return operators[key];
    }

    /**
     * @notice Calculate the deterministic address for an operator
     * @dev Uses CREATE2 formula: keccak256(0xff ++ address(this) ++ salt ++ keccak256(bytecode))
     */
    function computeAddress(OperatorConfig calldata config) external view returns (address operator) {
        bytes32 key = _computeKey(config);
        bytes memory bytecode = _getBytecode(config);
        bytes32 bytecodeHash = keccak256(bytecode);

        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), key, bytecodeHash)))));
    }

    /**
     * @notice Deploy an operator with full configuration
     * @dev Idempotent - returns existing operator if already deployed.
     *      Uses CREATE2 for deterministic addresses.
     * @param config The operator configuration
     * @return operator The operator address
     * @custom:security ARBITER LOCKOUT: If releaseCondition is address(0), the receiver can
     *         front-run an arbiter's updateStatus() by calling release() to drain capturableAmount,
     *         locking out the arbiter (post-escrow = receiver only). Always set a releaseCondition
     *         (e.g., EscrowPeriod) when using freeze or refund dispute flows.
     */
    function deployOperator(OperatorConfig calldata config) external returns (address operator) {
        // ============ CHECKS ============
        if (config.feeRecipient == address(0)) revert ZeroAddress();

        bytes32 key = _computeKey(config);

        // Return existing if already deployed (idempotent)
        if (operators[key] != address(0)) {
            return operators[key];
        }

        // ============ EFFECTS ============
        // Compute deterministic CREATE2 address before deployment (CEI pattern)
        bytes memory bytecode = _getBytecode(config);
        operator = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), key, keccak256(bytecode)))))
        );

        // Store before external interaction
        operators[key] = operator;

        emit OperatorDeployed(operator, config.feeRecipient, config.releaseCondition);

        // ============ INTERACTIONS ============
        // Deploy new operator - address is deterministic via CREATE2
        PaymentOperator.ConditionConfig memory conditions = PaymentOperator.ConditionConfig({
            authorizeCondition: config.authorizeCondition,
            authorizeRecorder: config.authorizeRecorder,
            chargeCondition: config.chargeCondition,
            chargeRecorder: config.chargeRecorder,
            releaseCondition: config.releaseCondition,
            releaseRecorder: config.releaseRecorder,
            refundInEscrowCondition: config.refundInEscrowCondition,
            refundInEscrowRecorder: config.refundInEscrowRecorder,
            refundPostEscrowCondition: config.refundPostEscrowCondition,
            refundPostEscrowRecorder: config.refundPostEscrowRecorder
        });
        address deployed = address(
            new PaymentOperator{salt: key}(
                ESCROW, PROTOCOL_FEE_CONFIG, config.feeRecipient, config.feeCalculator, conditions
            )
        );

        // Sanity check - CREATE2 address must match
        assert(deployed == operator);

        return operator;
    }

    // ============ Internal Helpers ============

    function _computeKey(OperatorConfig memory config) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                config.feeRecipient,
                config.feeCalculator,
                config.authorizeCondition,
                config.authorizeRecorder,
                config.chargeCondition,
                config.chargeRecorder,
                config.releaseCondition,
                config.releaseRecorder,
                config.refundInEscrowCondition,
                config.refundInEscrowRecorder,
                config.refundPostEscrowCondition,
                config.refundPostEscrowRecorder
            )
        );
    }

    function _getBytecode(OperatorConfig memory config) internal view returns (bytes memory) {
        // Create the ConditionConfig struct for encoding
        PaymentOperator.ConditionConfig memory conditions = PaymentOperator.ConditionConfig({
            authorizeCondition: config.authorizeCondition,
            authorizeRecorder: config.authorizeRecorder,
            chargeCondition: config.chargeCondition,
            chargeRecorder: config.chargeRecorder,
            releaseCondition: config.releaseCondition,
            releaseRecorder: config.releaseRecorder,
            refundInEscrowCondition: config.refundInEscrowCondition,
            refundInEscrowRecorder: config.refundInEscrowRecorder,
            refundPostEscrowCondition: config.refundPostEscrowCondition,
            refundPostEscrowRecorder: config.refundPostEscrowRecorder
        });

        return abi.encodePacked(
            type(PaymentOperator).creationCode,
            abi.encode(ESCROW, PROTOCOL_FEE_CONFIG, config.feeRecipient, config.feeCalculator, conditions)
        );
    }
}
