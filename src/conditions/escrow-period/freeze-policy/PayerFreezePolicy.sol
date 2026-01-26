// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IFreezePolicy} from "./IFreezePolicy.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title PayerFreezePolicy
 * @notice IFreezePolicy implementation that allows only the payer to freeze/unfreeze.
 * @dev Stateless policy contract - freeze state is owned by EscrowPeriodRecorder.
 *      Only determines authorization: the payer can freeze/unfreeze their own payments.
 *      Freeze duration is configurable at deployment.
 */
contract PayerFreezePolicy is IFreezePolicy {
    /// @notice Duration that payer freezes last (0 = permanent until unfrozen)
    uint256 public immutable FREEZE_DURATION;

    constructor(uint256 _freezeDuration) {
        FREEZE_DURATION = _freezeDuration;
    }

    /// @inheritdoc IFreezePolicy
    function canFreeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, address caller)
        external
        view
        override
        returns (bool allowed, uint256 duration)
    {
        allowed = caller == paymentInfo.payer;
        duration = FREEZE_DURATION;
    }

    /// @inheritdoc IFreezePolicy
    function canUnfreeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, address caller)
        external
        pure
        override
        returns (bool)
    {
        return caller == paymentInfo.payer;
    }
}
