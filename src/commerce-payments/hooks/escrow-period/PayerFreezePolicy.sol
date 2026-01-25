// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IFreezePolicy} from "./types/IFreezePolicy.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title PayerFreezePolicy
 * @notice IFreezePolicy implementation that allows only the payer to freeze/unfreeze.
 * @dev Stateless policy contract - freeze state is owned by EscrowPeriodCondition.
 *      Only determines authorization: the payer can freeze/unfreeze their own payments.
 */
contract PayerFreezePolicy is IFreezePolicy {
    /// @inheritdoc IFreezePolicy
    function canFreeze(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address caller
    ) external pure override returns (bool) {
        return caller == paymentInfo.payer;
    }

    /// @inheritdoc IFreezePolicy
    function canUnfreeze(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address caller
    ) external pure override returns (bool) {
        return caller == paymentInfo.payer;
    }
}
