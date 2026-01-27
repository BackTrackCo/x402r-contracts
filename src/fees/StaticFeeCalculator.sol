// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {IFeeCalculator} from "./IFeeCalculator.sol";

/**
 * @title StaticFeeCalculator
 * @notice Simple immutable fee calculator that always returns a fixed basis points value.
 */
contract StaticFeeCalculator is IFeeCalculator {
    uint256 public immutable FEE_BPS;

    constructor(uint256 _feeBps) {
        FEE_BPS = _feeBps;
    }

    /// @inheritdoc IFeeCalculator
    function calculateFee(AuthCaptureEscrow.PaymentInfo calldata, uint256, address)
        external
        view
        override
        returns (uint256 feeBps)
    {
        return FEE_BPS;
    }
}
