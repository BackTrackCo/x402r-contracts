// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ArbitrationOperatorAccess} from "./ArbitrationOperatorAccess.sol";
import {ZeroAddress, ZeroAmount} from "../../types/Errors.sol";
import {ZeroEscrow, ZeroArbiter} from "../types/Errors.sol";
import {
    TotalFeeRateExceedsMax,
    InvalidAuthorizationExpiry,
    InvalidFeeBps,
    InvalidFeeReceiver,
    UnauthorizedCaller
} from "../types/Errors.sol";
import {IReleaseCondition} from "../types/IReleaseCondition.sol";
import {IAuthorizable} from "../types/IAuthorizable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
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

    // ============ Core State ============
    AuthCaptureEscrow public immutable ESCROW;
    address public immutable ARBITER;
    mapping(bytes32 => AuthCaptureEscrow.PaymentInfo) public paymentInfos;

    // Payment indexing for discoverability
    mapping(address => bytes32[]) private payerPayments;
    mapping(address => bytes32[]) private receiverPayments;

    // ============ Fee Configuration ============
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public immutable MAX_TOTAL_FEE_RATE;
    uint256 public immutable PROTOCOL_FEE_PERCENTAGE;
    uint256 public immutable MAX_ARBITER_FEE_RATE;

    // Release condition contract - controls when funds can be released (verification logic)
    IReleaseCondition public immutable RELEASE_CONDITION;

    address public immutable protocolFeeRecipient;
    bool public feesEnabled;
    bool public immutable AUTHORIZATION_RESTRICTED;

    constructor(
        address _escrow,
        address _protocolFeeRecipient,
        uint256 _maxTotalFeeRate,
        uint256 _protocolFeePercentage,
        address _arbiter,
        address _owner,
        address _releaseCondition
    ) {
        if (_escrow == address(0)) revert ZeroEscrow();
        if (_arbiter == address(0)) revert ZeroArbiter();
        ESCROW = AuthCaptureEscrow(_escrow);
        ARBITER = _arbiter;
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

        // Check if condition supports IAuthorizable to see if we should restrict authorization
        bool restricted = false;
        try IERC165(_releaseCondition).supportsInterface(type(IAuthorizable).interfaceId) returns (bool supported) {
            restricted = supported;
        } catch {
            // If it doesn't support ERC165, assume not restricted
            restricted = false;
        }
        AUTHORIZATION_RESTRICTED = restricted;
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
        // ============ CHECKS ============
        if (AUTHORIZATION_RESTRICTED && msg.sender != address(RELEASE_CONDITION)) {
            revert UnauthorizedCaller();
        }
        if (paymentInfo.authorizationExpiry != type(uint48).max) revert InvalidAuthorizationExpiry();
        if (paymentInfo.minFeeBps != MAX_TOTAL_FEE_RATE || paymentInfo.maxFeeBps != MAX_TOTAL_FEE_RATE) {
            revert InvalidFeeBps();
        }
        if (paymentInfo.feeReceiver != address(this)) revert InvalidFeeReceiver();

        // ============ EFFECTS ============
        // Compute hash and update state before external call (CEI pattern)
        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);
        paymentInfos[paymentInfoHash] = paymentInfo;
        _addPayerPayment(paymentInfo.payer, paymentInfoHash);
        _addReceiverPayment(paymentInfo.receiver, paymentInfoHash);

        // ============ INTERACTIONS ============
        ESCROW.authorize(paymentInfo, amount, tokenCollector, collectorData);

        emit AuthorizationCreated(
            paymentInfoHash,
            paymentInfo.payer,
            paymentInfo.receiver,
            amount,
            block.timestamp
        );
    }

    /**
     * @notice Release funds to receiver
     * @dev Can be called by:
     *      1. RELEASE_CONDITION contract (validates conditions first)
     *      2. Payer directly (bypasses release condition - payer waives protection)
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to release
     */
    function release(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount
    ) external validOperator(paymentInfo) onlyAuthorizedOrPayer(paymentInfo, address(RELEASE_CONDITION)) {
        uint16 feeBps = uint16(MAX_TOTAL_FEE_RATE);
        address feeReceiver = address(this);

        // Forward to escrow - escrow validates payment exists
        ESCROW.capture(paymentInfo, amount, feeBps, feeReceiver);

        emit ReleaseExecuted(paymentInfo, amount, block.timestamp);
    }

    /**
     * @notice Refund funds while still in escrow (before capture)
     * @dev Only arbiter OR receiver can call. Returns escrowed funds to payer.
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to return to payer
     */
    function refundInEscrow(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint120 amount
    ) external validOperator(paymentInfo) onlyReceiverOrArbiter(paymentInfo, ARBITER) {
        // Forward to escrow's partialVoid - escrow validates payment exists
        ESCROW.partialVoid(paymentInfo, amount);

        // Compute hash only for event
        emit RefundExecuted(paymentInfo, paymentInfo.payer, amount);
    }

    /**
     * @notice Refund captured funds back to payer (after capture/release)
     * @dev Permission is enforced by the token collector (e.g., receiver must have approved it,
     *      or collectorData contains receiver's signature). Anyone can call, but refund only
     *      succeeds if the token collector can source the funds.
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to refund to payer
     * @param tokenCollector Address of the token collector that will source the refund
     * @param collectorData Data to pass to the token collector (e.g., signatures)
     */
    function refundPostEscrow(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external validOperator(paymentInfo) {
        // Forward to escrow's refund - token collector enforces permission
        ESCROW.refund(paymentInfo, amount, tokenCollector, collectorData);

        emit RefundExecuted(paymentInfo, paymentInfo.payer, uint120(amount));
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

    /// @notice Rescue any ETH accidentally sent to this contract
    /// @dev Solady's Ownable has payable functions; this allows recovery of any stuck ETH
    function rescueETH() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success,) = msg.sender.call{value: balance}("");
            require(success);
        }
    }

    // ============ View Functions ============

    /**
     * @notice Check if a payment exists (has been authorized)
     * @param paymentInfoHash The hash of the PaymentInfo
     * @return True if payment exists
     */
    function paymentExists(bytes32 paymentInfoHash) public view returns (bool) {
        return paymentInfos[paymentInfoHash].payer != address(0);
    }

    /**
     * @notice Get stored PaymentInfo for a given hash
     * @param paymentInfoHash The hash of the PaymentInfo
     * @return The stored PaymentInfo struct
     */
    function getPaymentInfo(bytes32 paymentInfoHash) public view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return paymentInfos[paymentInfoHash];
    }

    /**
     * @notice Check if payment is in escrow (has capturable amount)
     * @param paymentInfoHash The hash of the PaymentInfo
     * @return True if payment is in escrow
     */
    function isInEscrow(bytes32 paymentInfoHash) public view returns (bool) {
        (, uint120 capturableAmount,) = ESCROW.paymentState(paymentInfoHash);
        return capturableAmount > 0;
    }

    /**
     * @notice Get all payment hashes for a payer
     * @param payer The payer address
     * @return Array of payment info hashes
     */
    function getPayerPayments(address payer) external view returns (bytes32[] memory) {
        return payerPayments[payer];
    }

    /**
     * @notice Get all payment hashes for a receiver (merchant)
     * @param receiver The receiver address
     * @return Array of payment info hashes
     */
    function getReceiverPayments(address receiver) external view returns (bytes32[] memory) {
        return receiverPayments[receiver];
    }

    // ============ Internal Helpers ============

    /**
     * @notice Add payment hash to payer's list
     * @param payer The payer address
     * @param hash The payment info hash
     */
    function _addPayerPayment(address payer, bytes32 hash) internal {
        payerPayments[payer].push(hash);
    }

    /**
     * @notice Add payment hash to receiver's list
     * @param receiver The receiver address
     * @param hash The payment info hash
     */
    function _addReceiverPayment(address receiver, bytes32 hash) internal {
        receiverPayments[receiver].push(hash);
    }
}
