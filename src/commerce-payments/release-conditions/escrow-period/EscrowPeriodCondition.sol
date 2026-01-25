// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {ICanCondition} from "../../operator/types/ICanCondition.sol";
import {INoteCondition} from "../../operator/types/INoteCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {EscrowPeriodConditionAccess} from "./EscrowPeriodConditionAccess.sol";
import {
    InvalidEscrowPeriod,
    FundsFrozen,
    EscrowPeriodExpired,
    AlreadyFrozen,
    NotFrozen
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
 *         Implements both ICanCondition (for CAN_RELEASE) and INoteCondition (for NOTE_AUTHORIZE).
 *         Payer can bypass this via the CAN_BYPASS condition (typically PayerOnly) for can() checks
 *         and NOTE_BYPASS condition for note() calls.
 *         Supports freeze/unfreeze with optional policy-based authorization.
 *
 * @dev Pull Model Architecture:
 *      - Same contract address is passed to both NOTE_AUTHORIZE and CAN_RELEASE slots
 *      - note() records authorization time (called by operator after authorize) and delegates to NOTE_BYPASS if provided
 *      - can() checks escrow period with payer bypass via CAN_BYPASS
 *
 *      Operator Configuration:
 *      NOTE_AUTHORIZE = escrowPeriodCondition  // records auth time
 *      CAN_RELEASE = escrowPeriodCondition     // same contract! checks escrow period
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
contract EscrowPeriodCondition is ICanCondition, INoteCondition, EscrowPeriodConditionAccess {
    /// @notice Duration of the escrow period in seconds
    uint256 public immutable ESCROW_PERIOD;

    /// @notice Optional freeze policy contract (address(0) = no freeze support)
    IFreezePolicy public immutable FREEZE_POLICY;

    /// @notice Bypass condition for payer in can() checks (e.g., PayerOnly)
    address public immutable CAN_BYPASS;

    /// @notice Bypass condition for payer in note() calls (e.g., PayerOnly)
    address public immutable NOTE_BYPASS;

    /// @notice Stores the authorization time for each payment
    /// @dev Key: paymentInfoHash
    mapping(bytes32 => uint256) public authorizationTimes;

    /// @notice Tracks frozen payments
    /// @dev Key: paymentInfoHash
    mapping(bytes32 => bool) public frozen;

    constructor(uint256 _escrowPeriod, address _freezePolicy, address _canBypass, address _noteBypass) {
        if (_escrowPeriod == 0) revert InvalidEscrowPeriod();
        ESCROW_PERIOD = _escrowPeriod;
        FREEZE_POLICY = IFreezePolicy(_freezePolicy);
        CAN_BYPASS = _canBypass;
        NOTE_BYPASS = _noteBypass;
    }

    // ============ INoteCondition Implementation ============

    /**
     * @notice Record authorization time (called by operator in NOTE_AUTHORIZE slot)
     * @dev Must validate msg.sender == paymentInfo.operator for security.
     *      Also delegates to NOTE_BYPASS.note() if provided.
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount authorized
     * @param caller The address that called authorize
     */
    function note(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external override onlyOperator(paymentInfo.operator) {
        AuthCaptureEscrow escrow = IArbitrationOperator(paymentInfo.operator).ESCROW();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        authorizationTimes[paymentInfoHash] = block.timestamp;

        emit PaymentAuthorized(paymentInfo, block.timestamp);

        // Delegate to NOTE_BYPASS if provided
        if (address(NOTE_BYPASS) != address(0)) {
            try INoteCondition(NOTE_BYPASS).note(paymentInfo, amount, caller) {} catch {}
        }
    }

    // ============ ICanCondition Implementation ============

    /**
     * @notice Check if release is allowed (called by operator in CAN_RELEASE slot)
     * @dev Payer bypass via CAN_BYPASS (e.g., PayerOnly). If escrow period has passed
     *      and funds are not frozen, anyone can release.
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to release (passed to CAN_BYPASS)
     * @param caller The address attempting to release
     * @return True if release is allowed
     */
    function can(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external view override returns (bool) {
        // Payer bypass via CAN_BYPASS (e.g., PayerOnly)
        if (address(CAN_BYPASS) != address(0) && ICanCondition(CAN_BYPASS).can(paymentInfo, amount, caller)) {
            return true;
        }

        AuthCaptureEscrow escrow = IArbitrationOperator(paymentInfo.operator).ESCROW();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Check if frozen
        if (frozen[paymentInfoHash]) {
            return false;
        }

        // Check if payment was authorized (note() was called)
        uint256 authTime = authorizationTimes[paymentInfoHash];
        if (authTime == 0) {
            return false;
        }

        // Check if escrow period has passed
        return block.timestamp >= authTime + ESCROW_PERIOD;
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
