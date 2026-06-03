// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PaymentOperatorAccess} from "./PaymentOperatorAccess.sol";
import {ZeroAddress} from "../../types/Errors.sol";
import {ZeroEscrow, PreActionConditionNotMet, FeeTooHigh, FeeBoundsIncompatible} from "../types/Errors.sol";
import {ICondition} from "../../plugins/conditions/ICondition.sol";
import {IHook} from "../../plugins/hooks/IHook.sol";
import {
    AuthorizeExecuted,
    ChargeExecuted,
    CaptureExecuted,
    VoidExecuted,
    RefundExecuted,
    FeesDistributed
} from "../types/Events.sol";
import {IFeeCalculator} from "../../plugins/fees/static-fee-calculator/IFeeCalculator.sol";
import {ProtocolFeeConfig} from "../../plugins/fees/ProtocolFeeConfig.sol";

/**
 * @title PaymentOperator
 * @notice Generic operator contract with pluggable conditions for flexible payment authorization.
 *         Supports marketplace escrow, subscriptions, streaming, grants, and any custom payment flow.
 *
 * @dev Plugin Architecture:
 *      - Operator controls flow, conditions and hooks are composable plugins
 *      - 10 slots: 5 conditions (before checks) + 5 hooks (after state updates)
 *      - address(0) = default behavior (allow for conditions, no-op for hooks)
 *      - Conditions implement ICondition.check() -> returns bool (true = allowed)
 *      - Hooks implement IHook.run() -> updates state after action
 *      - Conditions can be composed using combinators (Or, And, Not)
 *
 *      Slots (one per action):
 *      - AUTHORIZE_PRE_ACTION_CONDITION / AUTHORIZE_POST_ACTION_HOOK
 *      - CHARGE_PRE_ACTION_CONDITION / CHARGE_POST_ACTION_HOOK
 *      - CAPTURE_PRE_ACTION_CONDITION / CAPTURE_POST_ACTION_HOOK
 *      - VOID_PRE_ACTION_CONDITION / VOID_POST_ACTION_HOOK
 *      - REFUND_PRE_ACTION_CONDITION / REFUND_POST_ACTION_HOOK
 *
 *      Flow for each action:
 *      User -> operator.action() -> [condition.check()?] -> escrow -> [hook.run()?]
 *
 * FEE SYSTEM (Modular, Additive):
 *      - Protocol fees come from shared ProtocolFeeConfig (timelocked swappable IFeeCalculator)
 *      - Operator fees come from per-operator IFeeCalculator (set at deploy, immutable)
 *      - totalFee = protocolFee + operatorFee (additive)
 *      - Protocol fees tracked per-token in mapping for accurate distribution
 *      - Fee recipients: protocolFeeRecipient on ProtocolFeeConfig, FEE_RECEIVER on operator
 *
 * ARCHITECTURE: Users call operator methods directly:
 *        User -> operator.authorize() -> escrow.authorize()
 *        User -> operator.charge()    -> escrow.charge()
 *        User -> operator.capture()   -> escrow.capture()
 *        User -> operator.void()      -> escrow.void()
 *        User -> operator.refund()    -> escrow.refund()
 */
contract PaymentOperator is ReentrancyGuardTransient, PaymentOperatorAccess {
    /// @notice Configuration struct for condition/hook slots
    struct PluginConfig {
        address authorizePreActionCondition;
        address authorizePostActionHook;
        address chargePreActionCondition;
        address chargePostActionHook;
        address capturePreActionCondition;
        address capturePostActionHook;
        address voidPreActionCondition;
        address voidPostActionHook;
        address refundPreActionCondition;
        address refundPostActionHook;
    }

    // ============ Core State ============
    AuthCaptureEscrow public immutable ESCROW;
    address public immutable FEE_RECEIVER;

    // ============ Fee Configuration (Modular) ============
    IFeeCalculator public immutable FEE_CALCULATOR;
    ProtocolFeeConfig public immutable PROTOCOL_FEE_CONFIG;
    mapping(address token => uint256) public accumulatedProtocolFees;

    /// @notice Fees locked at authorization time to prevent changes from breaking capture
    /// @dev Stores fee rates calculated at authorize() to use at capture()
    struct AuthorizedFees {
        uint16 totalFeeBps;
        uint16 protocolFeeBps;
    }

    mapping(bytes32 paymentInfoHash => AuthorizedFees) public authorizedFees;

    // ============ Condition Slots (before-action checks) ============
    // address(0) = always allow (default behavior)
    ICondition public immutable AUTHORIZE_PRE_ACTION_CONDITION;
    ICondition public immutable CHARGE_PRE_ACTION_CONDITION;
    ICondition public immutable CAPTURE_PRE_ACTION_CONDITION;
    ICondition public immutable VOID_PRE_ACTION_CONDITION;
    ICondition public immutable REFUND_PRE_ACTION_CONDITION;

    // ============ Hook Slots (after-action state updates) ============
    // address(0) = no-op (default behavior)
    IHook public immutable AUTHORIZE_POST_ACTION_HOOK;
    IHook public immutable CHARGE_POST_ACTION_HOOK;
    IHook public immutable CAPTURE_POST_ACTION_HOOK;
    IHook public immutable VOID_POST_ACTION_HOOK;
    IHook public immutable REFUND_POST_ACTION_HOOK;

    constructor(
        address _escrow,
        address _protocolFeeConfig,
        address _feeReceiver,
        address _feeCalculator,
        PluginConfig memory _conditions
    ) {
        if (_escrow == address(0)) revert ZeroEscrow();
        if (_feeReceiver == address(0)) revert ZeroAddress();
        if (_protocolFeeConfig == address(0)) revert ZeroAddress();

        ESCROW = AuthCaptureEscrow(_escrow);
        FEE_RECEIVER = _feeReceiver;
        PROTOCOL_FEE_CONFIG = ProtocolFeeConfig(_protocolFeeConfig);
        FEE_CALCULATOR = IFeeCalculator(_feeCalculator);

        // Set condition slots (address(0) = always allow)
        AUTHORIZE_PRE_ACTION_CONDITION = ICondition(_conditions.authorizePreActionCondition);
        CHARGE_PRE_ACTION_CONDITION = ICondition(_conditions.chargePreActionCondition);
        CAPTURE_PRE_ACTION_CONDITION = ICondition(_conditions.capturePreActionCondition);
        VOID_PRE_ACTION_CONDITION = ICondition(_conditions.voidPreActionCondition);
        REFUND_PRE_ACTION_CONDITION = ICondition(_conditions.refundPreActionCondition);

        // Set hook slots (address(0) = no-op)
        AUTHORIZE_POST_ACTION_HOOK = IHook(_conditions.authorizePostActionHook);
        CHARGE_POST_ACTION_HOOK = IHook(_conditions.chargePostActionHook);
        CAPTURE_POST_ACTION_HOOK = IHook(_conditions.capturePostActionHook);
        VOID_POST_ACTION_HOOK = IHook(_conditions.voidPostActionHook);
        REFUND_POST_ACTION_HOOK = IHook(_conditions.refundPostActionHook);
    }

    // ============ Internal Fee Calculation ============

    /**
     * @notice Calculate total fee (protocol + operator) for a payment action
     * @param paymentInfo The payment info struct
     * @param amount The payment amount
     * @return totalFeeBps Combined fee in basis points
     * @return protocolFeeBps_ Protocol fee in basis points
     */
    function _calculateFees(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount)
        internal
        view
        returns (uint16 totalFeeBps, uint16 protocolFeeBps_)
    {
        // Protocol fee from shared config (returns 0 if calculator is address(0))
        uint256 protocolFeeBps = PROTOCOL_FEE_CONFIG.getProtocolFeeBps(paymentInfo, amount, msg.sender);
        protocolFeeBps_ = uint16(protocolFeeBps);

        // Operator fee (from calculator, or 0 if no calculator)
        uint256 operatorFeeBps = 0;
        if (address(FEE_CALCULATOR) != address(0)) {
            operatorFeeBps = FEE_CALCULATOR.calculateFee(paymentInfo, amount, msg.sender);
        }

        uint256 combinedFeeBps = protocolFeeBps + operatorFeeBps;
        if (combinedFeeBps > 10000) revert FeeTooHigh();
        totalFeeBps = uint16(combinedFeeBps);
    }

    // ============ Payment Functions ============

    /**
     * @notice Authorize payment via Base Commerce Payments escrow
     * @dev Checks AUTHORIZE_PRE_ACTION_CONDITION, performs authorization, then calls AUTHORIZE_POST_ACTION_HOOK
     * @param paymentInfo PaymentInfo struct with required values:
     *        - operator == address(this)
     *        - feeReceiver == address(this)
     *        authorizationExpiry can be set to any value (use type(uint48).max for no expiry)
     * @param amount Amount to authorize
     * @param tokenCollector Address of the token collector
     * @param collectorData Data passed to both the token collector AND forwarded to
     *        AUTHORIZE_PRE_ACTION_CONDITION.check() and AUTHORIZE_POST_ACTION_HOOK.run() as the `data` parameter.
     *        NOTE: Dual-purpose — collector initialization data (e.g. ERC-3009 authorization
     *        params) AND hook data for conditions/hooks. A condition that decodes
     *        collectorData may conflict with collector-specific encoding. Callers packing
     *        both should use a structured encoding (e.g. abi.encode(collectorPayload, hookPayload)).
     */
    function authorize(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external nonReentrant validFees(paymentInfo) {
        if (address(AUTHORIZE_PRE_ACTION_CONDITION) != address(0)) {
            if (!AUTHORIZE_PRE_ACTION_CONDITION.check(paymentInfo, amount, msg.sender, collectorData)) {
                revert PreActionConditionNotMet();
            }
        }

        (uint16 totalFeeBps, uint16 protocolFeeBps) = _calculateFees(paymentInfo, amount);
        if (totalFeeBps < paymentInfo.minFeeBps || totalFeeBps > paymentInfo.maxFeeBps) {
            revert FeeBoundsIncompatible(totalFeeBps, paymentInfo.minFeeBps, paymentInfo.maxFeeBps);
        }

        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);

        // ============ INTERACTIONS ============
        ESCROW.authorize(paymentInfo, amount, tokenCollector, collectorData);

        // ============ EFFECTS (post-INTERACTIONS for strict CEI) ============
        // Same rationale as charge/capture: any future revert path (e.g. wrapping the
        // escrow call in try/catch) cannot leave authorizedFees mutated or events emitted
        // for an action that didn't go through.
        authorizedFees[paymentInfoHash] = AuthorizedFees({totalFeeBps: totalFeeBps, protocolFeeBps: protocolFeeBps});
        emit AuthorizeExecuted(paymentInfo, paymentInfoHash, paymentInfo.payer, paymentInfo.receiver, amount);

        if (address(AUTHORIZE_POST_ACTION_HOOK) != address(0)) {
            AUTHORIZE_POST_ACTION_HOOK.run(paymentInfo, amount, msg.sender, collectorData);
        }
    }

    /**
     * @notice Direct charge - collects payment and immediately transfers to receiver
     * @dev Checks CHARGE_PRE_ACTION_CONDITION, performs charge, then calls CHARGE_POST_ACTION_HOOK.
     *      Unlike authorize(), funds go directly to receiver (no escrow hold).
     *      Refunds are only possible via refund().
     *
     *      Signature note: this deliberately mirrors the canonical `AuthCaptureEscrow.charge`
     *      selector (`charge(PaymentInfo,uint256,address,bytes,uint16,address)` = `0x9e65819f`)
     *      so a facilitator that forwards the literal escrow `charge` selector to a smart-contract
     *      captureAuthorizer dispatches here. The auth-capture facilitator always encodes this
     *      6-arg escrow form for the `autoCapture` single-shot flow; a narrower 4-arg signature
     *      would expose a different selector, the forwarded call would find no matching function,
     *      hit the fallback, and revert. The two-phase `authorize` path needs no such alignment
     *      because the operator and escrow already share the identical 4-arg `authorize` selector
     *      (`0x41d66202`).
     *
     *      Fee handling — the operator owns the fee RATE, but the fee RECEIVER is delegated to the
     *      canonical escrow's own validation:
     *      - `feeReceiver` is passed straight through to the escrow. The escrow's `_validateFee`
     *        reverts unless it equals `paymentInfo.feeReceiver` (`InvalidFeeReceiver`) or rejects a
     *        zero receiver when a fee is due (`ZeroFeeReceiver`), and `validFees` already requires
     *        `paymentInfo.feeReceiver == address(this)`. So the only non-reverting value is this
     *        operator: a mismatched or zero arg reverts for free, fees can never be routed away from
     *        the operator (keeping `accumulatedProtocolFees` accounting sound), and no operator-level
     *        check is needed.
     *      - `feeBps` is IGNORED (left unnamed, which also avoids an unused-variable note) and
     *        recomputed internally. The facilitator passes `paymentInfo.minFeeBps` as a placeholder
     *        within the payer-signed `[minFeeBps, maxFeeBps]` range, NOT the actual fee, and the
     *        operator's protocol-fee accounting needs its own recomputed rate (still bounded by the
     *        range), so the supplied value cannot be forwarded.
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to charge
     * @param tokenCollector Address of the token collector
     * @param collectorData Data passed to both the token collector AND forwarded to
     *        CHARGE_PRE_ACTION_CONDITION.check() and CHARGE_POST_ACTION_HOOK.run() as the `data` parameter.
     *        NOTE: Dual-purpose — see authorize() for collision considerations.
     * @param feeReceiver Forwarded to the escrow, which requires it to equal paymentInfo.feeReceiver
     *        (pinned to address(this) by validFees); any other value reverts.
     */
    function charge(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData,
        uint16,
        address feeReceiver
    ) external nonReentrant validFees(paymentInfo) {
        if (address(CHARGE_PRE_ACTION_CONDITION) != address(0)) {
            if (!CHARGE_PRE_ACTION_CONDITION.check(paymentInfo, amount, msg.sender, collectorData)) {
                revert PreActionConditionNotMet();
            }
        }

        (uint16 totalFeeBps, uint16 protocolFeeBps) = _calculateFees(paymentInfo, amount);
        if (totalFeeBps < paymentInfo.minFeeBps || totalFeeBps > paymentInfo.maxFeeBps) {
            revert FeeBoundsIncompatible(totalFeeBps, paymentInfo.minFeeBps, paymentInfo.maxFeeBps);
        }
        uint256 protocolFeeAmount = (amount * protocolFeeBps) / 10000;

        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);

        // ============ INTERACTIONS ============
        // totalFeeBps is the internally recomputed rate (the caller's feeBps arg is ignored).
        // feeReceiver is passed through: escrow _validateFee reverts unless it equals
        // paymentInfo.feeReceiver, which validFees pins to address(this) — so fees land on the operator.
        ESCROW.charge(paymentInfo, amount, tokenCollector, collectorData, totalFeeBps, feeReceiver);

        // ============ EFFECTS (post-INTERACTIONS for strict CEI) ============
        // Done after the escrow call so that any future revert path (e.g. wrapping the
        // escrow call in try/catch) cannot leave fee state mutated or events emitted
        // for an action that didn't go through.
        accumulatedProtocolFees[paymentInfo.token] += protocolFeeAmount;
        emit ChargeExecuted(paymentInfo, paymentInfoHash, paymentInfo.payer, paymentInfo.receiver, amount);

        if (address(CHARGE_POST_ACTION_HOOK) != address(0)) {
            CHARGE_POST_ACTION_HOOK.run(paymentInfo, amount, msg.sender, collectorData);
        }
    }

    /**
     * @notice Capture authorized funds and transfer to receiver
     * @dev Checks CAPTURE_PRE_ACTION_CONDITION, performs escrow.capture, then calls CAPTURE_POST_ACTION_HOOK.
     *      Uses fees stored at authorization time to prevent protocol fee changes from breaking capture.
     *      `validFees` is required here for symmetry with authorize/charge: capture passes
     *      `feeReceiver = address(this)` to escrow, and `paymentInfo.feeReceiver != address(this)`
     *      would otherwise be mismatched. Upstream `_validateFee` also enforces this, but the
     *      modifier makes the local invariant explicit and survives future escrow refactors.
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to capture
     * @param data Arbitrary data forwarded to CAPTURE_PRE_ACTION_CONDITION.check() and CAPTURE_POST_ACTION_HOOK.run()
     */
    function capture(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount, bytes calldata data)
        external
        nonReentrant
        validFees(paymentInfo)
    {
        if (address(CAPTURE_PRE_ACTION_CONDITION) != address(0)) {
            if (!CAPTURE_PRE_ACTION_CONDITION.check(paymentInfo, amount, msg.sender, data)) {
                revert PreActionConditionNotMet();
            }
        }

        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);
        AuthorizedFees memory fees = authorizedFees[paymentInfoHash];
        uint256 protocolFeeAmount = (amount * fees.protocolFeeBps) / 10000;
        address feeReceiver = address(this);

        // ============ INTERACTIONS ============
        ESCROW.capture(paymentInfo, amount, fees.totalFeeBps, feeReceiver);

        // ============ EFFECTS (post-INTERACTIONS for strict CEI) ============
        accumulatedProtocolFees[paymentInfo.token] += protocolFeeAmount;
        emit CaptureExecuted(paymentInfo, paymentInfoHash, paymentInfo.payer, paymentInfo.receiver, amount);

        if (address(CAPTURE_POST_ACTION_HOOK) != address(0)) {
            CAPTURE_POST_ACTION_HOOK.run(paymentInfo, amount, msg.sender, data);
        }
    }

    /**
     * @notice Void an authorization, returning held funds to payer
     * @dev Checks VOID_PRE_ACTION_CONDITION with the current capturable amount, performs
     *      escrow.void, then calls VOID_POST_ACTION_HOOK. The condition receives the actual
     *      amount the void will return so amount-gated conditions (e.g. TVL limits, bounds
     *      checks) work correctly. Passing 0 here would silently bypass any amount-based gate.
     * @param paymentInfo PaymentInfo struct
     * @param data Arbitrary data forwarded to VOID_PRE_ACTION_CONDITION.check() and VOID_POST_ACTION_HOOK.run()
     */
    function void(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, bytes calldata data) external nonReentrant {
        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);
        (, uint120 capturableAmount,) = ESCROW.paymentState(paymentInfoHash);

        if (address(VOID_PRE_ACTION_CONDITION) != address(0)) {
            if (!VOID_PRE_ACTION_CONDITION.check(paymentInfo, capturableAmount, msg.sender, data)) {
                revert PreActionConditionNotMet();
            }
        }

        // ============ INTERACTIONS ============
        ESCROW.void(paymentInfo);

        // ============ EFFECTS (post-INTERACTIONS for strict CEI) ============
        emit VoidExecuted(paymentInfo, paymentInfoHash, paymentInfo.payer, paymentInfo.receiver);

        if (address(VOID_POST_ACTION_HOOK) != address(0)) {
            VOID_POST_ACTION_HOOK.run(paymentInfo, capturableAmount, msg.sender, data);
        }
    }

    /**
     * @notice Refund captured funds back to payer (after capture or charge)
     * @dev Checks REFUND_PRE_ACTION_CONDITION, performs escrow.refund, then calls REFUND_POST_ACTION_HOOK.
     *      Permission is enforced by the token collector (e.g., receiver must have approved it).
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to refund to payer
     * @param tokenCollector Address of the token collector that will source the refund
     * @param collectorData Data passed to both the token collector AND forwarded to
     *        REFUND_PRE_ACTION_CONDITION.check() and REFUND_POST_ACTION_HOOK.run() as the `data` parameter.
     *        NOTE: Dual-purpose — see authorize() for collision considerations.
     */
    function refund(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external nonReentrant {
        if (address(REFUND_PRE_ACTION_CONDITION) != address(0)) {
            if (!REFUND_PRE_ACTION_CONDITION.check(paymentInfo, amount, msg.sender, collectorData)) {
                revert PreActionConditionNotMet();
            }
        }

        bytes32 paymentInfoHash = ESCROW.getHash(paymentInfo);

        // ============ INTERACTIONS ============
        ESCROW.refund(paymentInfo, amount, tokenCollector, collectorData);

        // ============ EFFECTS (post-INTERACTIONS for strict CEI) ============
        emit RefundExecuted(paymentInfo, paymentInfoHash, paymentInfo.payer, paymentInfo.receiver, amount);

        if (address(REFUND_POST_ACTION_HOOK) != address(0)) {
            REFUND_POST_ACTION_HOOK.run(paymentInfo, amount, msg.sender, collectorData);
        }
    }

    /**
     * @notice Distribute collected fees to protocol and operator
     * @dev Protocol gets tracked accumulated amount, operator gets remainder
     * @param token The token address to distribute fees for
     */
    function distributeFees(address token) external nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        uint256 balance = SafeTransferLib.balanceOf(token, address(this));
        if (balance == 0) return;

        uint256 protocolShare = accumulatedProtocolFees[token];
        if (protocolShare > balance) {
            protocolShare = balance;
        }
        uint256 operatorShare = balance - protocolShare;

        accumulatedProtocolFees[token] = 0;

        emit FeesDistributed(token, protocolShare, operatorShare);

        if (protocolShare > 0) {
            SafeTransferLib.safeTransfer(token, PROTOCOL_FEE_CONFIG.getProtocolFeeRecipient(), protocolShare);
        }

        if (operatorShare > 0) {
            SafeTransferLib.safeTransfer(token, FEE_RECEIVER, operatorShare);
        }
    }
}
