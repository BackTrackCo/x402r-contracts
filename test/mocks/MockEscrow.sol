// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/**
 * @title MockEscrow
 * @notice Mock implementation of AuthCaptureEscrow for testing
 * @dev Simplified version that mimics the PaymentInfo-based interface
 */
contract MockEscrow {
    using SafeTransferLib for address;

    /// @notice Payment info struct (matches Base Commerce Payments)
    struct PaymentInfo {
        address operator;
        address payer;
        address receiver;
        address token;
        uint120 maxAmount;
        uint48 preApprovalExpiry;
        uint48 authorizationExpiry;
        uint48 refundExpiry;
        uint16 minFeeBps;
        uint16 maxFeeBps;
        address feeReceiver;
        uint256 salt;
    }

    /// @notice Payment state struct
    struct PaymentState {
        bool hasCollectedPayment;
        uint120 capturableAmount;
        uint120 refundableAmount;
    }

    bytes32 public constant PAYMENT_INFO_TYPEHASH = keccak256(
        "PaymentInfo(address operator,address payer,address receiver,address token,uint120 maxAmount,uint48 preApprovalExpiry,uint48 authorizationExpiry,uint48 refundExpiry,uint16 minFeeBps,uint16 maxFeeBps,address feeReceiver,uint256 salt)"
    );

    mapping(bytes32 => PaymentState) public paymentState;

    // Events
    event PaymentAuthorized(bytes32 indexed paymentInfoHash, PaymentInfo paymentInfo, uint256 amount, address tokenCollector);
    event PaymentCaptured(bytes32 indexed paymentInfoHash, uint256 amount, uint16 feeBps, address feeReceiver);
    event PaymentVoided(bytes32 indexed paymentInfoHash, uint256 amount);
    event PaymentPartiallyVoided(bytes32 indexed paymentInfoHash, uint256 amount, uint256 remainingCapturable);
    event PaymentRefunded(bytes32 indexed paymentInfoHash, uint256 amount, address tokenCollector);

    // Errors
    error InvalidSender(address sender, address expected);
    error ZeroAmount();
    error PaymentAlreadyCollected(bytes32 paymentInfoHash);
    error InsufficientAuthorization(bytes32 paymentInfoHash, uint256 authorizedAmount, uint256 requestedAmount);
    error ZeroAuthorization(bytes32 paymentInfoHash);
    error PartialVoidExceedsCapturable(uint256 requested, uint256 available);
    error RefundExceedsCapture(uint256 refund, uint256 captured);

    function authorize(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata /* collectorData */
    ) external {
        if (msg.sender != paymentInfo.operator) revert InvalidSender(msg.sender, paymentInfo.operator);
        if (amount == 0) revert ZeroAmount();

        bytes32 paymentInfoHash = getHash(paymentInfo);
        if (paymentState[paymentInfoHash].hasCollectedPayment) revert PaymentAlreadyCollected(paymentInfoHash);

        // Transfer tokens from payer to this contract (mock escrow)
        paymentInfo.token.safeTransferFrom(paymentInfo.payer, address(this), amount);

        paymentState[paymentInfoHash] = PaymentState({
            hasCollectedPayment: true,
            capturableAmount: uint120(amount),
            refundableAmount: 0
        });

        emit PaymentAuthorized(paymentInfoHash, paymentInfo, amount, tokenCollector);
    }

    function charge(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata, /* collectorData */
        uint16 feeBps,
        address feeReceiver
    ) external {
        if (msg.sender != paymentInfo.operator) revert InvalidSender(msg.sender, paymentInfo.operator);
        if (amount == 0) revert ZeroAmount();

        bytes32 paymentInfoHash = getHash(paymentInfo);
        if (paymentState[paymentInfoHash].hasCollectedPayment) revert PaymentAlreadyCollected(paymentInfoHash);

        // Transfer tokens from payer to this contract (then immediately out)
        paymentInfo.token.safeTransferFrom(paymentInfo.payer, address(this), amount);

        // Calculate fee and transfer to receiver immediately
        uint256 feeAmount = (amount * feeBps) / 10000;
        uint256 receiverAmount = amount - feeAmount;

        if (feeAmount > 0 && feeReceiver != address(0)) {
            paymentInfo.token.safeTransfer(feeReceiver, feeAmount);
        }
        if (receiverAmount > 0) {
            paymentInfo.token.safeTransfer(paymentInfo.receiver, receiverAmount);
        }

        // Set state: no capturable (already transferred), but refundable for post-capture refunds
        paymentState[paymentInfoHash] = PaymentState({
            hasCollectedPayment: true,
            capturableAmount: 0,
            refundableAmount: uint120(amount)
        });

        emit PaymentAuthorized(paymentInfoHash, paymentInfo, amount, tokenCollector);
    }

    function capture(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        uint16 feeBps,
        address feeReceiver
    ) external {
        if (msg.sender != paymentInfo.operator) revert InvalidSender(msg.sender, paymentInfo.operator);
        if (amount == 0) revert ZeroAmount();

        bytes32 paymentInfoHash = getHash(paymentInfo);
        PaymentState memory state = paymentState[paymentInfoHash];

        if (state.capturableAmount < amount) {
            revert InsufficientAuthorization(paymentInfoHash, state.capturableAmount, amount);
        }

        // Update state
        paymentState[paymentInfoHash].capturableAmount = state.capturableAmount - uint120(amount);
        paymentState[paymentInfoHash].refundableAmount = state.refundableAmount + uint120(amount);

        // Calculate fee and transfer
        uint256 feeAmount = (amount * feeBps) / 10000;
        uint256 receiverAmount = amount - feeAmount;

        if (feeAmount > 0 && feeReceiver != address(0)) {
            paymentInfo.token.safeTransfer(feeReceiver, feeAmount);
        }
        if (receiverAmount > 0) {
            paymentInfo.token.safeTransfer(paymentInfo.receiver, receiverAmount);
        }

        emit PaymentCaptured(paymentInfoHash, amount, feeBps, feeReceiver);
    }

    function void(PaymentInfo calldata paymentInfo) external {
        if (msg.sender != paymentInfo.operator) revert InvalidSender(msg.sender, paymentInfo.operator);

        bytes32 paymentInfoHash = getHash(paymentInfo);
        uint256 authorizedAmount = paymentState[paymentInfoHash].capturableAmount;
        if (authorizedAmount == 0) revert ZeroAuthorization(paymentInfoHash);

        paymentState[paymentInfoHash].capturableAmount = 0;

        // Return tokens to payer
        paymentInfo.token.safeTransfer(paymentInfo.payer, authorizedAmount);

        emit PaymentVoided(paymentInfoHash, authorizedAmount);
    }

    function partialVoid(PaymentInfo calldata paymentInfo, uint120 amount) external {
        if (msg.sender != paymentInfo.operator) revert InvalidSender(msg.sender, paymentInfo.operator);
        if (amount == 0) revert ZeroAmount();

        bytes32 paymentInfoHash = getHash(paymentInfo);
        uint120 capturableAmount = paymentState[paymentInfoHash].capturableAmount;

        if (amount > capturableAmount) revert PartialVoidExceedsCapturable(amount, capturableAmount);

        paymentState[paymentInfoHash].capturableAmount = capturableAmount - amount;

        // Return tokens to payer
        paymentInfo.token.safeTransfer(paymentInfo.payer, amount);

        emit PaymentPartiallyVoided(paymentInfoHash, amount, capturableAmount - amount);
    }

    function refund(
        PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata /* collectorData */
    ) external {
        if (msg.sender != paymentInfo.operator) revert InvalidSender(msg.sender, paymentInfo.operator);
        if (amount == 0) revert ZeroAmount();

        bytes32 paymentInfoHash = getHash(paymentInfo);
        uint120 captured = paymentState[paymentInfoHash].refundableAmount;
        if (captured < amount) revert RefundExceedsCapture(amount, captured);

        paymentState[paymentInfoHash].refundableAmount = captured - uint120(amount);

        // Transfer tokens from receiver back to payer (mock - assumes receiver approved)
        paymentInfo.token.safeTransferFrom(paymentInfo.receiver, paymentInfo.payer, amount);

        emit PaymentRefunded(paymentInfoHash, amount, tokenCollector);
    }

    function getHash(PaymentInfo calldata paymentInfo) public view returns (bytes32) {
        bytes32 paymentInfoHash = keccak256(abi.encode(PAYMENT_INFO_TYPEHASH, paymentInfo));
        return keccak256(abi.encode(block.chainid, address(this), paymentInfoHash));
    }
}
