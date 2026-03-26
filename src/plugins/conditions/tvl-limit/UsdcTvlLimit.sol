// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICondition} from "../ICondition.sol";

/// @title UsdcTvlLimit
/// @notice Limits total USDC in escrow and blocks all other tokens
/// @dev Temporary safety measure for early mainnet deployment.
///      Deploy a new condition to change limits or add tokens.
///
/// SECURITY NOTE - Griefing Vector:
///      This contract uses balanceOf() to determine TVL, which is susceptible to
///      direct-transfer griefing. An attacker can send USDC directly to the ESCROW
///      address (bypassing authorize()), inflating the apparent TVL and potentially
///      blocking legitimate authorizations. The attack is uneconomical because the
///      attacker permanently loses the sent tokens (they cannot be recovered from
///      the escrow). For production use beyond the temporary safety measure, replace
///      with internal escrow accounting that only counts operator-authorized deposits.
contract UsdcTvlLimit is ICondition {
    /// @notice The address to check TVL against (escrow or token store)
    address public immutable ESCROW;

    /// @notice The USDC token address
    address public immutable USDC;

    /// @notice Maximum USDC allowed in escrow
    uint256 public immutable LIMIT;

    error ZeroAddress();

    constructor(address escrow, address usdc, uint256 limit) {
        if (escrow == address(0)) revert ZeroAddress();
        if (usdc == address(0)) revert ZeroAddress();
        ESCROW = escrow;
        USDC = usdc;
        LIMIT = limit;
    }

    /// @notice Check if payment is allowed
    /// @dev Returns false for non-USDC tokens. For USDC, checks TVL limit.
    /// @param paymentInfo The payment information containing token address
    /// @param amount The payment amount
    /// @return allowed True if USDC and within TVL limit
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount, address, bytes calldata)
        external
        view
        override
        returns (bool allowed)
    {
        // Block all non-USDC tokens
        if (paymentInfo.token != USDC) return false;

        // Check TVL limit
        uint256 currentTvl = IERC20(USDC).balanceOf(ESCROW);
        return currentTvl + amount <= LIMIT;
    }
}
