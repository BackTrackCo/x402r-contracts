// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {Ownable} from "solady/auth/Ownable.sol";
import {PaymentOperator} from "./arbitration/PaymentOperator.sol";
import {ZeroAddress, ZeroAmount} from "../types/Errors.sol";
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
 *      - Factory owner controls fee settings on all deployed operators
 *      - Works with Base Commerce Payments as designed
 *
 * OWNERSHIP: Uses Solady's Ownable with built-in 2-step transfer for safety:
 *        1. New owner calls requestOwnershipHandover()
 *        2. Current owner calls completeOwnershipHandover(newOwner) within 48 hours
 *        This prevents accidental transfers to wrong addresses.
 *
 * PRODUCTION REQUIREMENT: Owner MUST be a multisig (e.g., Gnosis Safe) in production.
 *        Single EOA ownership is only acceptable for testing/development.
 *        Factory owner controls all deployed operators, so securing this is critical.
 */
contract PaymentOperatorFactory is Ownable {
    /// @notice Configuration struct for deploying operators
    struct OperatorConfig {
        address feeRecipient;
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
    address public immutable PROTOCOL_FEE_RECIPIENT;
    uint256 public immutable MAX_TOTAL_FEE_RATE;
    uint256 public immutable PROTOCOL_FEE_PERCENTAGE;

    // keccak256(config) => operator address
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
     *      Factory owner becomes the operator owner (controls fee settings).
     *      Uses CREATE2 for deterministic addresses.
     * @param config The operator configuration
     * @return operator The operator address
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
                ESCROW,
                PROTOCOL_FEE_RECIPIENT,
                MAX_TOTAL_FEE_RATE,
                PROTOCOL_FEE_PERCENTAGE,
                config.feeRecipient,
                owner(),
                conditions
            )
        );

        // Sanity check - CREATE2 address must match
        assert(deployed == operator);

        return operator;
    }

    /// @notice Rescue any ETH accidentally sent to this contract
    /// @dev Solady's Ownable has payable functions; this allows recovery of any stuck ETH
    function rescueETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success,) = msg.sender.call{value: balance}("");
            require(success);
        }
    }

    // ============ Internal Helpers ============

    function _computeKey(OperatorConfig memory config) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                config.feeRecipient,
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
            abi.encode(
                ESCROW,
                PROTOCOL_FEE_RECIPIENT,
                MAX_TOTAL_FEE_RATE,
                PROTOCOL_FEE_PERCENTAGE,
                config.feeRecipient,
                owner(),
                conditions
            )
        );
    }
}
