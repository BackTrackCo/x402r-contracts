// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @notice Emitted when a payment is frozen
/// @param paymentInfo The PaymentInfo struct
/// @param caller The address that froze the payment
event PaymentFrozen(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed caller);

/// @notice Emitted when a payment is unfrozen
/// @param paymentInfo The PaymentInfo struct
/// @param caller The address that unfroze the payment
event PaymentUnfrozen(AuthCaptureEscrow.PaymentInfo paymentInfo, address indexed caller);

/// @notice Emitted when a Freeze contract is deployed via factory
/// @param freeze Address of the deployed Freeze contract
/// @param freezeCondition ICondition that authorizes freeze calls
/// @param unfreezeCondition ICondition that authorizes unfreeze calls
/// @param freezeDuration Duration that freezes last (0 = permanent)
/// @param escrowPeriodContract Address of the optional escrow period contract (address(0) if unconstrained)
event FreezeDeployed(
    address indexed freeze,
    address freezeCondition,
    address unfreezeCondition,
    uint256 freezeDuration,
    address escrowPeriodContract
);
