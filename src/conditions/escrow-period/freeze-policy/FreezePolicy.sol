// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IFreezePolicy} from "./IFreezePolicy.sol";
import {ICondition} from "../../ICondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title FreezePolicy
 * @notice Generic IFreezePolicy that delegates authorization to ICondition contracts.
 * @dev Composes with existing conditions (PayerCondition, ReceiverCondition, ArbiterCondition,
 *      AlwaysTrueCondition) and combinators (AndCondition, OrCondition, NotCondition).
 *
 *      Example configurations:
 *      - Payer freeze/unfreeze (3 days): (PayerCondition, PayerCondition, 3 days)
 *      - Payer freeze, Arbiter unfreeze: (PayerCondition, ArbiterCondition, 0)
 *      - Anyone freeze, Receiver unfreeze: (AlwaysTrueCondition, ReceiverCondition, 7 days)
 */
contract FreezePolicy is IFreezePolicy {
    /// @notice Condition that authorizes freeze calls
    ICondition public immutable FREEZE_CONDITION;

    /// @notice Condition that authorizes unfreeze calls
    ICondition public immutable UNFREEZE_CONDITION;

    /// @notice Duration that freezes last (0 = permanent until unfrozen)
    uint256 public immutable FREEZE_DURATION;

    constructor(address _freezeCondition, address _unfreezeCondition, uint256 _freezeDuration) {
        FREEZE_CONDITION = ICondition(_freezeCondition);
        UNFREEZE_CONDITION = ICondition(_unfreezeCondition);
        FREEZE_DURATION = _freezeDuration;
    }

    /// @inheritdoc IFreezePolicy
    function canFreeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, address caller)
        external
        view
        override
        returns (bool allowed, uint256 duration)
    {
        allowed = FREEZE_CONDITION.check(paymentInfo, caller);
        duration = FREEZE_DURATION;
    }

    /// @inheritdoc IFreezePolicy
    function canUnfreeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, address caller)
        external
        view
        override
        returns (bool)
    {
        return UNFREEZE_CONDITION.check(paymentInfo, caller);
    }
}
