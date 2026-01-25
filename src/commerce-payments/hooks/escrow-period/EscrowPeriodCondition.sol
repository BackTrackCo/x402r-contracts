// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IBeforeHook} from "../types/IBeforeHook.sol";
import {IAfterHook} from "../types/IAfterHook.sol";
import {AUTHORIZE, RELEASE} from "../types/Actions.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {EscrowPeriodConditionAccess} from "./EscrowPeriodConditionAccess.sol";
import {
    InvalidEscrowPeriod,
    FundsFrozen,
    EscrowPeriodNotPassed,
    EscrowPeriodExpired,
    AlreadyFrozen,
    NotFrozen,
    NotAuthorized
} from "./types/Errors.sol";
import {IFreezePolicy} from "./types/IFreezePolicy.sol";
import {PaymentAuthorized, PaymentFrozen, PaymentUnfrozen} from "./types/Events.sol";

// Forward declaration for reading escrow
interface IArbitrationOperator {
    function ESCROW() external view returns (AuthCaptureEscrow);
}

/**
 * @title EscrowPeriodCondition
 * @notice Release condition that enforces a time-based escrow period before funds can be released.
 *         Implements both IBeforeHook and IAfterHook with action routing.
 *         Uses payerBypass modifier for payer to release immediately.
 *         Supports freeze/unfreeze with optional policy-based authorization.
 *
 * @dev Pull Model Architecture:
 *      - Same contract address is passed as both BEFORE_HOOK and AFTER_HOOK to operator
 *      - afterAction(AUTHORIZE) records authorization time
 *      - beforeAction(RELEASE) checks escrow period (payer bypasses via modifier)
 *      - Other actions are no-op / allow-through
 *
 *      Operator Configuration:
 *      BEFORE_HOOK = escrowPeriodCondition
 *      AFTER_HOOK = escrowPeriodCondition
 *
 * TRUST ASSUMPTIONS:
 *      - FREEZE_POLICY: The freeze policy contract is trusted to correctly determine who can
 *        freeze/unfreeze payments. A malicious policy could deny legitimate freezes or allow
 *        unauthorized freezes. Operators should audit the policy implementation before deployment.
 *      - Timestamp: Uses block.timestamp for time-based escrow periods.
 *        On L1 (Ethereum mainnet): Miners can manipulate timestamps within ~15 seconds.
 *        For ESCROW_PERIOD values < 1 minute on L1, this manipulation could be significant.
 *        Recommended minimum ESCROW_PERIOD is 5 minutes (300 seconds) for L1 deployments.
 *        On L2s (e.g., Base): The sequencer (Coinbase for Base) controls timestamps and is
 *        already trusted for transaction ordering. Shorter periods (< 1 minute) are acceptable
 *        on L2s given the sequencer trust model and faster block times (~2 seconds on Base).
 */
contract EscrowPeriodCondition is IBeforeHook, IAfterHook, EscrowPeriodConditionAccess {
    /// @notice Duration of the escrow period in seconds
    uint256 public immutable ESCROW_PERIOD;

    /// @notice Optional freeze policy contract (address(0) = no freeze support)
    IFreezePolicy public immutable FREEZE_POLICY;

    /// @notice Stores the authorization time for each payment
    /// @dev Key: paymentInfoHash
    mapping(bytes32 => uint256) public authorizationTimes;

    /// @notice Tracks frozen payments
    /// @dev Key: paymentInfoHash
    mapping(bytes32 => bool) public frozen;

    constructor(uint256 _escrowPeriod, address _freezePolicy) {
        if (_escrowPeriod == 0) revert InvalidEscrowPeriod();
        ESCROW_PERIOD = _escrowPeriod;
        FREEZE_POLICY = IFreezePolicy(_freezePolicy);
    }

    // ============ IAfterHook Implementation ============

    /**
     * @notice Called after an action occurs
     * @dev Routes based on action parameter. Only AUTHORIZE is handled.
     * @param action The action that occurred
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount (unused)
     * @param caller The address that called authorize (unused)
     */
    function afterAction(
        bytes4 action,
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external override onlyOperator(paymentInfo.operator) {
        if (action == AUTHORIZE) {
            _afterAuthorize(paymentInfo);
        }
        // Other actions: no-op

        // Silence unused variable warnings
        (amount, caller);
    }

    /**
     * @notice Internal authorize handler - records authorization time
     * @param paymentInfo PaymentInfo struct
     */
    function _afterAuthorize(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo
    ) internal {
        AuthCaptureEscrow escrow = IArbitrationOperator(paymentInfo.operator).ESCROW();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        authorizationTimes[paymentInfoHash] = block.timestamp;

        emit PaymentAuthorized(paymentInfo, block.timestamp);
    }

    // ============ IBeforeHook Implementation ============

    /**
     * @notice Check if action is allowed
     * @dev Routes based on action parameter. Only RELEASE is guarded.
     * @param action The action being performed
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount (unused)
     * @param caller The address attempting the action
     */
    function beforeAction(
        bytes4 action,
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external view override {
        if (action == RELEASE) {
            _beforeRelease(paymentInfo, caller);
        }
        // Other actions: allow through (no revert)

        // Silence unused variable warning
        (amount);
    }

    /**
     * @notice Internal release check with payer bypass
     * @dev Payer can release immediately without waiting for escrow period
     * @param paymentInfo PaymentInfo struct
     * @param caller The address attempting the release
     */
    function _beforeRelease(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address caller
    ) internal view payerBypass(paymentInfo, caller) {
        AuthCaptureEscrow escrow = IArbitrationOperator(paymentInfo.operator).ESCROW();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Check if frozen
        if (frozen[paymentInfoHash]) {
            revert FundsFrozen();
        }

        // Check if payment was authorized (afterAction was called)
        uint256 authTime = authorizationTimes[paymentInfoHash];
        if (authTime == 0) {
            revert NotAuthorized();
        }

        // Check if escrow period has passed
        if (block.timestamp < authTime + ESCROW_PERIOD) {
            revert EscrowPeriodNotPassed();
        }
    }

    // ============ Freeze Functions ============

    /**
     * @notice Freeze a payment to block release
     * @dev Only callable during escrow period. Authorization checked via FREEZE_POLICY.
     * @param paymentInfo PaymentInfo struct for the payment to freeze
     */
    function freeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo)
        external
        requireFreezePolicy(FREEZE_POLICY)
        authorizedToFreeze(FREEZE_POLICY, paymentInfo)
    {
        AuthCaptureEscrow escrow = IArbitrationOperator(paymentInfo.operator).ESCROW();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // ============ CHECKS ============
        // Check escrow period hasn't expired
        uint256 authTime = authorizationTimes[paymentInfoHash];
        if (authTime == 0 || block.timestamp >= authTime + ESCROW_PERIOD) {
            revert EscrowPeriodExpired();
        }

        if (frozen[paymentInfoHash]) revert AlreadyFrozen();

        // ============ EFFECTS ============
        frozen[paymentInfoHash] = true;

        emit PaymentFrozen(paymentInfo, msg.sender);
    }

    /**
     * @notice Unfreeze a payment to allow release
     * @dev No escrow period check - unfreezing should always be allowed.
     *      Authorization checked via FREEZE_POLICY.
     * @param paymentInfo PaymentInfo struct for the payment to unfreeze
     */
    function unfreeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo)
        external
        requireFreezePolicy(FREEZE_POLICY)
        authorizedToUnfreeze(FREEZE_POLICY, paymentInfo)
    {
        AuthCaptureEscrow escrow = IArbitrationOperator(paymentInfo.operator).ESCROW();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // ============ CHECKS ============
        if (!frozen[paymentInfoHash]) revert NotFrozen();

        // ============ EFFECTS ============
        frozen[paymentInfoHash] = false;

        emit PaymentUnfrozen(paymentInfo, msg.sender);
    }

    // ============ View Functions ============

    /**
     * @notice Get the authorization time for a payment
     * @param paymentInfo PaymentInfo struct
     * @return The timestamp when the payment was authorized (0 if not authorized through this contract)
     */
    function getAuthorizationTime(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (uint256) {
        AuthCaptureEscrow escrow = IArbitrationOperator(paymentInfo.operator).ESCROW();
        return authorizationTimes[escrow.getHash(paymentInfo)];
    }

    /**
     * @notice Check if a payment is frozen
     * @param paymentInfo PaymentInfo struct
     * @return True if the payment is frozen
     */
    function isFrozen(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (bool) {
        AuthCaptureEscrow escrow = IArbitrationOperator(paymentInfo.operator).ESCROW();
        return frozen[escrow.getHash(paymentInfo)];
    }
}
