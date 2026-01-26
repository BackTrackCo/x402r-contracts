// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

/**
 * @title PaymentState
 * @notice Explicit payment lifecycle states for ArbitrationOperator
 *
 * STATE MACHINE:
 * ==============
 *
 *     ┌──────────────┐  authorize()   ┌──────────────┐  release()   ┌──────────────┐
 *     │ NonExistent  │ ────────────▶  │  InEscrow    │ ──────────▶  │  Released    │
 *     └──────────────┘                └──────────────┘              └──────────────┘
 *                                            │                             │
 *                                            │                             │
 *                              void/reclaim  │  refundPostEscrow (full)    │
 *                              refundInEscrow│  or refundExpiry passed     │
 *                              (full)        │                             │
 *                                            ▼                             ▼
 *                                     ┌─────────────────────────────────────────┐
 *                                     │              Settled                    │
 *                                     │  (no funds in escrow or refundable)     │
 *                                     └─────────────────────────────────────────┘
 *
 *     TRANSITIONS:
 *     - NonExistent → InEscrow: authorize()
 *     - InEscrow → InEscrow: partial refundInEscrow() (reduces capturableAmount)
 *     - InEscrow → Released: release() / capture()
 *     - InEscrow → Settled: full refundInEscrow(), void(), or reclaim()
 *     - InEscrow → Expired: authorizationExpiry passed (payer can reclaim)
 *     - Released → Released: partial refundPostEscrow() (reduces refundableAmount)
 *     - Released → Settled: full refundPostEscrow() or refundExpiry passed
 *     - Expired → Settled: reclaim() called by payer
 *
 *     FREEZE STATES (EscrowPeriodCondition only):
 *     - InEscrow can be frozen/unfrozen via condition.freeze()/unfreeze()
 *     - Frozen payments block release through condition (payer bypass still works)
 *     - Freeze state is tracked in EscrowPeriodCondition, not in escrow
 *
 * ESCROW FIELDS (from AuthCaptureEscrow.paymentState):
 *     - hasCollectedPayment: true if authorize() or charge() was called
 *     - capturableAmount: Funds in escrow that can be captured or voided
 *     - refundableAmount: Captured funds eligible for refund (within refundExpiry)
 */
enum PaymentState {
    /// @notice Payment has never been authorized through this operator
    NonExistent,

    /// @notice Payment authorized, funds locked in escrow (capturableAmount > 0)
    InEscrow,

    /// @notice Funds released to receiver, may still be refundable (refundableAmount > 0)
    Released,

    /// @notice Payment settled - no funds in escrow or refundable
    /// @dev Could be: voided before capture, fully refunded, or refund period expired
    ///      Escrow doesn't track capture history, so these are indistinguishable
    Settled,

    /// @notice Authorization expired, payer can reclaim via escrow.reclaim()
    Expired
}
