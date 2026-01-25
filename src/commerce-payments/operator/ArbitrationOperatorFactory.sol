// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {Ownable} from "solady/auth/Ownable.sol";
import {ArbitrationOperator} from "./arbitration/ArbitrationOperator.sol";
import {ZeroAddress, ZeroAmount} from "../types/Errors.sol";
import {OperatorDeployed} from "./types/Events.sol";

/**
 * @title ArbitrationOperatorFactory
 * @notice Factory contract that deploys ArbitrationOperator instances for x402r/Chamba.
 *         Each unique (arbiter, hooks) configuration gets its own operator contract.
 *
 * @dev Pull Model Architecture:
 *      - Operators have 2 hook slots: BEFORE_HOOK and AFTER_HOOK
 *      - address(0) = default behavior (AlwaysAllow for BEFORE, NoOp for AFTER)
 *      - Hooks receive action parameter (AUTHORIZE, RELEASE, REFUND_IN_ESCROW, REFUND_POST_ESCROW)
 *      - Client signs ERC-3009 with operator in PaymentInfo, committing to arbiter and hooks
 *      - Factory owner controls fee settings on all deployed operators
 *      - Works with Base Commerce Payments as designed
 */
contract ArbitrationOperatorFactory is Ownable {
    // Immutable configuration shared by all deployed operators
    address public immutable ESCROW;
    address public immutable PROTOCOL_FEE_RECIPIENT;
    uint256 public immutable MAX_TOTAL_FEE_RATE;
    uint256 public immutable PROTOCOL_FEE_PERCENTAGE;

    // keccak256(arbiter, hooks...) => operator address
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
     * @param arbiter The arbiter address for dispute resolution
     * @param beforeHook BEFORE_HOOK address (address(0) = always allow)
     * @param afterHook AFTER_HOOK address (address(0) = no-op)
     * @return operator The operator address (address(0) if not deployed)
     */
    function getOperator(
        address arbiter,
        address beforeHook,
        address afterHook
    ) external view returns (address) {
        bytes32 key = _computeKey(arbiter, beforeHook, afterHook);
        return operators[key];
    }

    /**
     * @notice Calculate the deterministic address for an operator
     * @dev Uses CREATE2 formula: keccak256(0xff ++ address(this) ++ salt ++ keccak256(bytecode))
     */
    function computeAddress(
        address arbiter,
        address beforeHook,
        address afterHook
    ) external view returns (address operator) {
        bytes32 key = _computeKey(arbiter, beforeHook, afterHook);
        bytes memory bytecode = _getBytecode(arbiter, beforeHook, afterHook);
        bytes32 bytecodeHash = keccak256(bytecode);

        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            key,
            bytecodeHash
        )))));
    }

    /**
     * @notice Deploy an operator with full configuration
     * @dev Idempotent - returns existing operator if already deployed.
     *      Factory owner becomes the operator owner (controls fee settings).
     *      Uses CREATE2 for deterministic addresses.
     * @param arbiter The arbiter address for dispute resolution
     * @param beforeHook BEFORE_HOOK address (address(0) = always allow)
     * @param afterHook AFTER_HOOK address (address(0) = no-op)
     * @return operator The operator address
     */
    function deployOperator(
        address arbiter,
        address beforeHook,
        address afterHook
    ) external returns (address operator) {
        // ============ CHECKS ============
        if (arbiter == address(0)) revert ZeroAddress();

        bytes32 key = _computeKey(arbiter, beforeHook, afterHook);

        // Return existing if already deployed (idempotent)
        if (operators[key] != address(0)) {
            return operators[key];
        }

        // ============ EFFECTS ============
        // Compute deterministic CREATE2 address before deployment (CEI pattern)
        bytes memory bytecode = _getBytecode(arbiter, beforeHook, afterHook);
        operator = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            key,
            keccak256(bytecode)
        )))));

        // Store before external interaction
        operators[key] = operator;

        emit OperatorDeployed(operator, arbiter, beforeHook);

        // ============ INTERACTIONS ============
        // Deploy new operator - address is deterministic via CREATE2
        address deployed = address(new ArbitrationOperator{salt: key}(
            ESCROW,
            PROTOCOL_FEE_RECIPIENT,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            arbiter,
            owner(),
            beforeHook,
            afterHook
        ));

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

    function _computeKey(
        address arbiter,
        address beforeHook,
        address afterHook
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(arbiter, beforeHook, afterHook));
    }

    function _getBytecode(
        address arbiter,
        address beforeHook,
        address afterHook
    ) internal view returns (bytes memory) {
        return abi.encodePacked(
            type(ArbitrationOperator).creationCode,
            abi.encode(
                ESCROW,
                PROTOCOL_FEE_RECIPIENT,
                MAX_TOTAL_FEE_RATE,
                PROTOCOL_FEE_PERCENTAGE,
                arbiter,
                owner(),
                beforeHook,
                afterHook
            )
        );
    }
}
