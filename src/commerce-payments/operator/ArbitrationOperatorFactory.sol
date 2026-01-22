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
 *         Each unique (arbiter, releaseCondition) pair gets its own operator contract.
 *
 * @dev Design rationale:
 *      - Operators are keyed by (arbiter, releaseCondition) - no time-based escrow
 *      - Release is controlled entirely by the releaseCondition contract (verification logic)
 *      - Client signs ERC-3009 with operator in PaymentInfo, committing to arbiter and verification terms
 *      - Factory owner controls fee settings on all deployed operators
 *      - Works with Base Commerce Payments as designed
 */
contract ArbitrationOperatorFactory is Ownable {
    // Immutable configuration shared by all deployed operators
    address public immutable ESCROW;
    address public immutable PROTOCOL_FEE_RECIPIENT;
    uint256 public immutable MAX_TOTAL_FEE_RATE;
    uint256 public immutable PROTOCOL_FEE_PERCENTAGE;

    // keccak256(arbiter, releaseCondition) => operator address
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
     * @notice Get the operator address for a given arbiter and release condition
     * @param arbiter The arbiter address for dispute resolution
     * @param releaseCondition The release condition contract address (verification logic)
     * @return operator The operator address (address(0) if not deployed)
     */
    function getOperator(address arbiter, address releaseCondition) external view returns (address) {
        bytes32 key = keccak256(abi.encodePacked(arbiter, releaseCondition));
        return operators[key];
    }

    /**
     * @notice Calculate the deterministic address for an operator
     * @dev Uses CREATE2 formula: keccak256(0xff ++ address(this) ++ salt ++ keccak256(bytecode))
     * @param arbiter The arbiter address
     * @param releaseCondition The release condition contract address
     * @return operator The predicted operator address
     */
    function computeAddress(address arbiter, address releaseCondition) external view returns (address operator) {
        bytes32 key = keccak256(abi.encodePacked(arbiter, releaseCondition));

        bytes memory bytecode = abi.encodePacked(
            type(ArbitrationOperator).creationCode,
            abi.encode(
                ESCROW,
                PROTOCOL_FEE_RECIPIENT,
                MAX_TOTAL_FEE_RATE,
                PROTOCOL_FEE_PERCENTAGE,
                arbiter,
                owner(),
                releaseCondition
            )
        );

        bytes32 bytecodeHash = keccak256(bytecode);

        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            key,
            bytecodeHash
        )))));
    }

    /**
     * @notice Deploy an operator for a given arbiter and release condition
     * @dev Idempotent - returns existing operator if already deployed.
     *      Factory owner becomes the operator owner (controls fee settings).
     *      Uses CREATE2 for deterministic addresses.
     * @param arbiter The arbiter address for dispute resolution
     * @param releaseCondition The release condition contract address (verification logic, required)
     * @return operator The operator address
     */
    function deployOperator(address arbiter, address releaseCondition) external returns (address operator) {
        if (arbiter == address(0)) revert ZeroAddress();
        if (releaseCondition == address(0)) revert ZeroAddress();

        bytes32 key = keccak256(abi.encodePacked(arbiter, releaseCondition));

        // Return existing if already deployed (idempotent)
        if (operators[key] != address(0)) {
            return operators[key];
        }

        // Deploy new operator with arbiter and release condition baked in
        // Factory owner becomes operator owner (controls fee settings)
        // Uses CREATE2 (salt: key) for deterministic address
        operator = address(new ArbitrationOperator{salt: key}(
            ESCROW,
            PROTOCOL_FEE_RECIPIENT,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE,
            arbiter,
            owner(),
            releaseCondition
        ));

        operators[key] = operator;

        emit OperatorDeployed(operator, arbiter, releaseCondition);

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
}
