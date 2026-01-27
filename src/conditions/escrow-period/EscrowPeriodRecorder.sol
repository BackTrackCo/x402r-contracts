// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {AuthorizationTimeRecorder, IArbitrationOperator} from "../AuthorizationTimeRecorder.sol";
import {IFreezePolicy} from "./freeze-policy/IFreezePolicy.sol";
import {
    InvalidEscrowPeriod,
    FundsFrozen,
    EscrowPeriodExpired,
    AlreadyFrozen,
    NotFrozen,
    NoFreezePolicy,
    UnauthorizedFreeze,
    Unauthorized
} from "./types/Errors.sol";
import {PaymentFrozen, PaymentUnfrozen} from "./types/Events.sol";

/**
 * @title EscrowPeriodRecorder
 * @notice Extends AuthorizationTimeRecorder with escrow period enforcement and freeze/unfreeze state.
 *         Provides state that EscrowPeriodCondition reads from.
 *
 * @dev Inherits from AuthorizationTimeRecorder for timestamp recording.
 *      Adds freeze state management on top:
 *      - frozenUntil: when each payment's freeze expires
 *      - freeze()/unfreeze(): manage freeze state
 *      - ESCROW_PERIOD: duration constraint
 *      - FREEZE_POLICY: who can freeze/unfreeze
 *
 * TRUST ASSUMPTIONS:
 *      - FREEZE_POLICY: The freeze policy contract is trusted to correctly determine who can
 *        freeze/unfreeze payments. A malicious policy could deny legitimate freezes or allow
 *        unauthorized freezes. Operators should audit the policy implementation before deployment.
 *      - Timestamp: Uses block.timestamp for time-based escrow periods.
 *
 * SECURITY NOTE - Freeze/Release Race Condition:
 *      At the exact moment the escrow period expires (block.timestamp == authTime + ESCROW_PERIOD):
 *      - freeze() will revert with EscrowPeriodExpired
 *      - EscrowPeriodCondition.check() will return true (release allowed)
 *
 *      MEV RISK: A malicious block builder could censor/delay a payer's freeze transaction
 *      until after the escrow period expires, allowing the receiver to release.
 *
 *      MITIGATIONS (in order of importance):
 *      1. FREEZE EARLY: If you anticipate a dispute, freeze immediately - don't wait until
 *         the escrow period is about to expire. Freezing early eliminates the race entirely.
 *      2. PRIVATE MEMPOOL: If freezing near the deadline, submit via Flashbots Protect or
 *         MEV Blocker to prevent transaction censorship and front-running.
 *      3. MONITOR: Watch for release attempts and be prepared to freeze proactively.
 *
 *      The ~12 second block window is small, but freezing early is the only way to fully
 *      eliminate the risk. There is no on-chain solution that prevents races at deadline
 *      boundaries without adding commit-reveal complexity.
 */
contract EscrowPeriodRecorder is AuthorizationTimeRecorder {
    /// @notice Duration of the escrow period in seconds
    uint256 public immutable ESCROW_PERIOD;

    /// @notice Optional freeze policy contract (address(0) = no freeze support)
    IFreezePolicy public immutable FREEZE_POLICY;

    /// @notice Tracks when freeze expires for each payment (0 = not frozen)
    /// @dev Key: paymentInfoHash, Value: timestamp when freeze expires
    mapping(bytes32 => uint256) public frozenUntil;

    constructor(uint256 _escrowPeriod, address _freezePolicy) {
        if (_escrowPeriod == 0) revert InvalidEscrowPeriod();
        ESCROW_PERIOD = _escrowPeriod;
        FREEZE_POLICY = IFreezePolicy(_freezePolicy);
    }

    // Note: record() inherited from AuthorizationTimeRecorder

    // ============ Freeze Functions ============

    /**
     * @notice Freeze a payment to block release
     * @dev Only callable during escrow period. Authorization and duration from FREEZE_POLICY.
     * @param paymentInfo PaymentInfo struct for the payment to freeze
     */
    function freeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        // Check freeze policy exists
        if (address(FREEZE_POLICY) == address(0)) revert NoFreezePolicy();

        // Check authorization via policy and get freeze duration
        (bool allowed, uint256 freezeDuration) = FREEZE_POLICY.canFreeze(paymentInfo, msg.sender);
        if (!allowed) revert UnauthorizedFreeze();

        bytes32 paymentInfoHash = _getPaymentHash(paymentInfo);

        // Check escrow period hasn't expired
        uint256 authTime = authorizationTimes[paymentInfoHash];
        if (authTime == 0 || block.timestamp >= authTime + ESCROW_PERIOD) {
            revert EscrowPeriodExpired();
        }

        if (frozenUntil[paymentInfoHash] > block.timestamp) revert AlreadyFrozen();

        // Calculate freeze expiration based on policy-provided duration
        uint256 freezeExpiry;
        if (freezeDuration == 0) {
            // Permanent freeze (until manually unfrozen)
            freezeExpiry = type(uint256).max;
        } else {
            freezeExpiry = block.timestamp + freezeDuration;
        }
        frozenUntil[paymentInfoHash] = freezeExpiry;

        emit PaymentFrozen(paymentInfo, msg.sender);
    }

    /**
     * @notice Unfreeze a payment to allow release
     * @dev No escrow period check - unfreezing should always be allowed.
     *      Authorization checked via FREEZE_POLICY.
     * @param paymentInfo PaymentInfo struct for the payment to unfreeze
     */
    function unfreeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        // Check freeze policy exists
        if (address(FREEZE_POLICY) == address(0)) revert NoFreezePolicy();

        // Check authorization via policy
        if (!FREEZE_POLICY.canUnfreeze(paymentInfo, msg.sender)) revert UnauthorizedFreeze();

        bytes32 paymentInfoHash = _getPaymentHash(paymentInfo);

        if (frozenUntil[paymentInfoHash] <= block.timestamp) revert NotFrozen();

        frozenUntil[paymentInfoHash] = 0;

        emit PaymentUnfrozen(paymentInfo, msg.sender);
    }

    // ============ View Functions ============

    // Note: getAuthorizationTime() inherited from AuthorizationTimeRecorder

    /**
     * @notice Check if a payment is currently frozen (not expired)
     * @param paymentInfo PaymentInfo struct
     * @return True if the payment is frozen and freeze hasn't expired
     */
    function isFrozen(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (bool) {
        return frozenUntil[_getPaymentHash(paymentInfo)] > block.timestamp;
    }

    /**
     * @notice Check if escrow period has passed for a payment
     * @param paymentInfo PaymentInfo struct
     * @return passed True if escrow period has passed
     * @return authTime The authorization timestamp
     */
    function isEscrowPeriodPassed(AuthCaptureEscrow.PaymentInfo calldata paymentInfo)
        external
        view
        returns (bool passed, uint256 authTime)
    {
        bytes32 paymentInfoHash = _getPaymentHash(paymentInfo);
        authTime = authorizationTimes[paymentInfoHash];
        if (authTime == 0) {
            return (false, 0);
        }
        passed = block.timestamp >= authTime + ESCROW_PERIOD;
    }
}
