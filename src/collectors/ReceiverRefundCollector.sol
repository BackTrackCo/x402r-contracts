// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TokenCollector} from "commerce-payments/collectors/TokenCollector.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/// @title ReceiverRefundCollector
///
/// @notice Collect refunds using ERC-20 allowances from receivers (merchants)
///
/// @dev Mirrors OperatorRefundCollector but pulls from `paymentInfo.receiver` instead of `paymentInfo.operator`.
///      The receiver pre-approves a refund budget via `token.approve(collectorAddress, amount)`.
///      When `refundPostEscrow()` is called, this collector transfers from the receiver's wallet to the token store.
contract ReceiverRefundCollector is TokenCollector {
    /// @inheritdoc TokenCollector
    TokenCollector.CollectorType public constant override collectorType = TokenCollector.CollectorType.Refund;

    /// @notice Constructor
    ///
    /// @param authCaptureEscrow_ AuthCaptureEscrow singleton that calls to collect tokens
    constructor(address authCaptureEscrow_) TokenCollector(authCaptureEscrow_) {}

    /// @inheritdoc TokenCollector
    ///
    /// @dev Transfers from receiver directly to token store, requiring previous ERC-20 allowance set by receiver on this token collector
    function _collectTokens(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        address tokenStore,
        uint256 amount,
        bytes calldata
    ) internal override {
        SafeERC20.safeTransferFrom(IERC20(paymentInfo.token), paymentInfo.receiver, tokenStore, amount);
    }
}
