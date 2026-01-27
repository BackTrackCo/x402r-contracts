// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title IFeeCalculator
 * @notice Pure fee calculation interface for modular fee system
 * @dev Implementations return fee in basis points for a given payment action.
 *      Used by both protocol-level and operator-level fee calculators.
 */
interface IFeeCalculator {
    /// @notice Calculate fee in basis points for a payment action
    /// @param paymentInfo The payment info struct
    /// @param amount The payment amount
    /// @param caller The address initiating the action
    /// @return feeBps The fee in basis points (e.g., 50 = 0.5%)
    function calculateFee(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external view returns (uint256 feeBps);
}
