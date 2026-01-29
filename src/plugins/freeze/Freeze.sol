// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {ICondition} from "../conditions/ICondition.sol";
import {IFreezePolicy} from "./freeze-policy/IFreezePolicy.sol";
import {EscrowPeriod} from "../escrow-period/EscrowPeriod.sol";
import {ZeroAddress} from "../../types/Errors.sol";
import {FreezeWindowExpired, UnauthorizedFreeze, AlreadyFrozen, NotFrozen} from "./types/Errors.sol";
import {PaymentFrozen, PaymentUnfrozen} from "./types/Events.sol";

/**
 * @title Freeze
 * @notice Standalone ICondition that blocks release when a payment is frozen.
 *         Manages freeze/unfreeze state with optional escrow period time constraint.
 *
 * @dev Implements ICondition: check() returns false when frozen (blocks release).
 *      Does NOT inherit BaseRecorder — uses ESCROW.getHash() directly for payment hash computation.
 *
 *      FREEZE_POLICY is required (constructor reverts on address(0)) — defines WHO can
 *      freeze/unfreeze and for HOW LONG.
 *
 *      ESCROW_PERIOD_CONTRACT is optional (address(0) = freeze is unconstrained by time).
 *      When set, freeze() calls isDuringEscrowPeriod() and reverts with FreezeWindowExpired
 *      if it returns false — this naturally rejects both non-authorized payments (authTime == 0)
 *      and post-expiry freezes in one call.
 *
 * COMPOSITION PATTERN:
 *      - Escrow period only:  releaseCondition = escrowPeriod
 *      - Freeze only:         releaseCondition = freeze
 *      - Both:                releaseCondition = AndCondition([escrowPeriod, freeze])
 *
 * TRUST ASSUMPTIONS:
 *      - FREEZE_POLICY: Trusted to correctly determine who can freeze/unfreeze payments.
 *        A malicious policy could deny legitimate freezes or allow unauthorized freezes.
 *        Operators should audit the policy implementation before deployment.
 *
 * SECURITY NOTE - Freeze/Release Race Condition:
 *      When composed with EscrowPeriod via AndCondition, at the exact moment the escrow
 *      period expires:
 *      - freeze() will revert with FreezeWindowExpired
 *      - EscrowPeriod.check() will return true (release allowed)
 *
 *      MEV RISK: A malicious block builder could censor/delay a payer's freeze transaction
 *      until after the escrow period expires, allowing the receiver to release.
 *
 *      MITIGATIONS:
 *      1. FREEZE EARLY: Freeze immediately when anticipating a dispute.
 *      2. PRIVATE MEMPOOL: Submit via Flashbots Protect or MEV Blocker near the deadline.
 *      3. MONITOR: Watch for release attempts and freeze proactively.
 */
contract Freeze is ICondition {
    /// @notice Escrow contract for payment hash computation
    AuthCaptureEscrow public immutable ESCROW;

    /// @notice Freeze policy contract (required — defines who can freeze/unfreeze)
    IFreezePolicy public immutable FREEZE_POLICY;

    /// @notice Optional escrow period contract (address(0) = freeze unconstrained by time)
    EscrowPeriod public immutable ESCROW_PERIOD_CONTRACT;

    /// @notice Tracks when freeze expires for each payment (0 = not frozen)
    /// @dev Key: paymentInfoHash, Value: timestamp when freeze expires
    mapping(bytes32 => uint256) public frozenUntil;

    constructor(address _freezePolicy, address _escrowPeriodContract, address _escrow) {
        if (_freezePolicy == address(0)) revert ZeroAddress();
        if (_escrow == address(0)) revert ZeroAddress();
        FREEZE_POLICY = IFreezePolicy(_freezePolicy);
        ESCROW_PERIOD_CONTRACT = EscrowPeriod(_escrowPeriodContract);
        ESCROW = AuthCaptureEscrow(_escrow);
    }

    // ============ ICondition Implementation ============

    /**
     * @notice Check if release is allowed (not frozen)
     * @param paymentInfo PaymentInfo struct
     * @return allowed True if payment is not frozen
     */
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256, address)
        external
        view
        override(ICondition)
        returns (bool allowed)
    {
        return !_isFrozen(paymentInfo);
    }

    // ============ Freeze Functions ============

    /**
     * @notice Freeze a payment to block release
     * @dev When ESCROW_PERIOD_CONTRACT is set, only callable during the escrow period.
     *      Authorization and duration from FREEZE_POLICY.
     * @param paymentInfo PaymentInfo struct for the payment to freeze
     */
    function freeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        // Check authorization via policy and get freeze duration
        (bool allowed, uint256 freezeDuration) = FREEZE_POLICY.canFreeze(paymentInfo, msg.sender);
        if (!allowed) revert UnauthorizedFreeze();

        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);

        // If escrow period contract is set, verify we're within the escrow period
        if (address(ESCROW_PERIOD_CONTRACT) != address(0)) {
            if (!ESCROW_PERIOD_CONTRACT.isDuringEscrowPeriod(paymentInfo)) {
                revert FreezeWindowExpired();
            }
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
     * @dev No escrow period check — unfreezing should always be allowed.
     *      Authorization checked via FREEZE_POLICY.
     * @param paymentInfo PaymentInfo struct for the payment to unfreeze
     */
    function unfreeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        // Check authorization via policy
        if (!FREEZE_POLICY.canUnfreeze(paymentInfo, msg.sender)) revert UnauthorizedFreeze();

        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);

        if (frozenUntil[paymentInfoHash] <= block.timestamp) revert NotFrozen();

        frozenUntil[paymentInfoHash] = 0;

        emit PaymentUnfrozen(paymentInfo, msg.sender);
    }

    // ============ View Functions ============

    /**
     * @notice Check if a payment is currently frozen (not expired)
     * @param paymentInfo PaymentInfo struct
     * @return True if the payment is frozen and freeze hasn't expired
     */
    function isFrozen(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (bool) {
        return _isFrozen(paymentInfo);
    }

    /**
     * @dev Internal frozen check
     */
    function _isFrozen(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) internal view returns (bool) {
        return frozenUntil[ESCROW.getHash(paymentInfo)] > block.timestamp;
    }
}
