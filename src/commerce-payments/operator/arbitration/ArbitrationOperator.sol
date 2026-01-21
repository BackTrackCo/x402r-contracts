// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ArbitrationOperatorAccess} from "./ArbitrationOperatorAccess.sol";
import {ZeroAddress, ZeroAmount} from "../../types/Errors.sol";
import {
    TotalFeeRateExceedsMax,
    ReleaseLocked,
    InvalidAuthorizationExpiry,
    InvalidRefundExpiry,
    InvalidFeeBps,
    InvalidFeeReceiver
} from "../types/Errors.sol";
import {IReleaseCondition} from "../types/IReleaseCondition.sol";
import {
    AuthorizationCreated,
    ReleaseExecuted,
    RefundExecuted,
    ProtocolFeesEnabledUpdated,
    FeesDistributed
} from "../types/Events.sol";

/**
 * @title ArbitrationOperator
 * @notice Operator contract for x402r - condition-based escrow release for Chamba universal execution protocol.
 *         Anyone (agents, robots, humans) can post jobs, anyone can execute them, payment held in escrow
 *         until verification via release condition contract.
 *
 * @dev Key features:
 *      - Release controlled by external IReleaseCondition contract (verification logic)
 *      - Immutable arbiter config for dispute resolution
 *      - Arbiter OR receiver can trigger refunds via partialVoid
 *      - Uses PaymentInfo struct from Base Commerce Payments for x402-escrow compatibility
 *      - Escrow is source of truth; operator stores PaymentInfo for indexing only
 */
contract ArbitrationOperator is Ownable, ArbitrationOperatorAccess {

    // Fee configuration
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public immutable MAX_TOTAL_FEE_RATE;
    uint256 public immutable PROTOCOL_FEE_PERCENTAGE;
    uint256 public immutable MAX_ARBITER_FEE_RATE;

    // Release condition contract - controls when funds can be released (verification logic)
    IReleaseCondition public immutable RELEASE_CONDITION;

    address public protocolFeeRecipient;
    bool public feesEnabled;

    constructor(
        address _escrow,
        address _protocolFeeRecipient,
        uint256 _maxTotalFeeRate,
        uint256 _protocolFeePercentage,
        address _arbiter,
        address _owner,
        address _releaseCondition
    ) ArbitrationOperatorAccess(_escrow, _arbiter) {
        if (_protocolFeeRecipient == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        if (_releaseCondition == address(0)) revert ZeroAddress();
        _initializeOwner(_owner);
        if (_maxTotalFeeRate == 0) revert ZeroAmount();
        if (_protocolFeePercentage > 100) revert TotalFeeRateExceedsMax();

        protocolFeeRecipient = _protocolFeeRecipient;
        feesEnabled = false;

        MAX_TOTAL_FEE_RATE = _maxTotalFeeRate;
        PROTOCOL_FEE_PERCENTAGE = _protocolFeePercentage;
        MAX_ARBITER_FEE_RATE = (_maxTotalFeeRate * (100 - _protocolFeePercentage)) / 100;
        RELEASE_CONDITION = IReleaseCondition(_releaseCondition);
    }

    // ============ Owner Functions ============

    /**
     * @notice Enable or disable protocol fees
     */
    function setFeesEnabled(bool enabled) external onlyOwner {
        feesEnabled = enabled;
        emit ProtocolFeesEnabledUpdated(enabled);
    }

    // ============ Payment Functions ============

    /**
     * @notice Authorize payment via Base Commerce Payments escrow
     * @dev Uses exact same interface as AuthCaptureEscrow.authorize()
     *      Funds held in escrow until RELEASE_CONDITION.canRelease() returns true.
     * @param paymentInfo PaymentInfo struct with required values:
     *        - operator == address(this)
     *        - authorizationExpiry == type(uint48).max
     *        - refundExpiry == type(uint48).max
     *        - minFeeBps == maxFeeBps == MAX_TOTAL_FEE_RATE
     *        - feeReceiver == address(this)
     * @param amount Amount to authorize
     * @param tokenCollector Address of the token collector
     * @param collectorData Data to pass to the token collector
     */
    function authorize(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external validOperator(paymentInfo) {
        // Validate required paymentInfo fields
        if (paymentInfo.authorizationExpiry != type(uint48).max) revert InvalidAuthorizationExpiry();
        if (paymentInfo.refundExpiry != type(uint48).max) revert InvalidRefundExpiry();
        if (paymentInfo.minFeeBps != MAX_TOTAL_FEE_RATE || paymentInfo.maxFeeBps != MAX_TOTAL_FEE_RATE) {
            revert InvalidFeeBps();
        }
        if (paymentInfo.feeReceiver != address(this)) revert InvalidFeeReceiver();

        // Forward to escrow
        ESCROW.authorize(paymentInfo, amount, tokenCollector, collectorData);

        // Compute hash once for indexing
        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);

        // Store PaymentInfo for indexing (not for validation)
        paymentInfos[paymentInfoHash] = paymentInfo;

        // Index by payer and receiver for discoverability
        _addPayerPayment(paymentInfo.payer, paymentInfoHash);
        _addReceiverPayment(paymentInfo.receiver, paymentInfoHash);

        emit AuthorizationCreated(
            paymentInfoHash,
            paymentInfo.payer,
            paymentInfo.receiver,
            amount,
            block.timestamp
        );
    }

    /**
     * @notice Release funds to receiver when condition is met
     * @dev Only receiver can call. Release only allowed when RELEASE_CONDITION.canRelease() returns true.
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to release
     */
    function release(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount
    ) external validOperator(paymentInfo) onlyReceiver(paymentInfo) {
        // Check release condition (verification logic)
        if (!RELEASE_CONDITION.canRelease(paymentInfo, amount)) {
            revert ReleaseLocked();
        }

        uint16 feeBps = uint16(MAX_TOTAL_FEE_RATE);
        address feeReceiver = address(this);

        // Forward to escrow - escrow validates payment exists
        ESCROW.capture(paymentInfo, amount, feeBps, feeReceiver);

        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);
        emit ReleaseExecuted(paymentInfoHash, amount, block.timestamp);
    }

    /**
     * @notice Refund funds while still in escrow (before capture)
     * @dev Only arbiter OR receiver can call. Returns escrowed funds to payer.
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to return to payer
     */
    function escrowRefund(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint120 amount
    ) external validOperator(paymentInfo) onlyReceiverOrArbiter(paymentInfo) {
        // Forward to escrow's partialVoid - escrow validates payment exists
        ESCROW.partialVoid(paymentInfo, amount);

        // Compute hash only for event
        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);
        emit RefundExecuted(paymentInfoHash, paymentInfo.payer, amount);
    }

    /**
     * @notice Distribute collected fees to protocol and arbiter
     * @param token The token address to distribute fees for
     */
    function distributeFees(address token) external {
        if (token == address(0)) revert ZeroAddress();
        uint256 balance = SafeTransferLib.balanceOf(token, address(this));
        if (balance == 0) return;

        uint256 protocolAmount = 0;
        uint256 arbiterAmount = 0;

        if (feesEnabled) {
            protocolAmount = (balance * PROTOCOL_FEE_PERCENTAGE) / 100;
            arbiterAmount = balance - protocolAmount;
        } else {
            arbiterAmount = balance;
        }

        if (protocolAmount > 0) {
            SafeTransferLib.safeTransfer(token, protocolFeeRecipient, protocolAmount);
        }

        if (arbiterAmount > 0) {
            SafeTransferLib.safeTransfer(token, ARBITER, arbiterAmount);
        }

        emit FeesDistributed(token, protocolAmount, arbiterAmount);
    }
}
