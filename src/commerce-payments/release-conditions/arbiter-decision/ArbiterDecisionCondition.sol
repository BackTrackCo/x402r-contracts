// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {ICanCondition} from "../../operator/types/ICanCondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

// Forward declaration for reading arbiter
interface IArbitrationOperator {
    function ARBITER() external view returns (address);
}

/**
 * @title ArbiterDecisionCondition
 * @notice Release condition where arbiter or payer (via FALLBACK) can release funds.
 *         Implements ICanCondition for the CAN_RELEASE slot.
 *
 * @dev Pull Model Architecture:
 *      - Payer bypass via FALLBACK (e.g., PayerOnly)
 *      - Arbiter can always release
 *      - Reads arbiter from the operator via paymentInfo.operator.ARBITER()
 *
 *      Operator Configuration:
 *      CAN_RELEASE = arbiterDecisionCondition  // wraps PayerOnly, adds arbiter
 */
contract ArbiterDecisionCondition is ICanCondition {
    /// @notice Fallback condition for payer bypass (e.g., PayerOnly)
    ICanCondition public immutable FALLBACK;

    constructor(address _fallback) {
        FALLBACK = ICanCondition(_fallback);
    }

    /**
     * @notice Check if release is allowed
     * @dev Payer bypass via FALLBACK. Arbiter can also release.
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to release
     * @param caller The address attempting to release
     * @return True if release is allowed
     */
    function can(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address caller
    ) external view override returns (bool) {
        // Payer bypass via fallback (e.g., PayerOnly)
        if (address(FALLBACK) != address(0) && FALLBACK.can(paymentInfo, amount, caller)) {
            return true;
        }
        
        // Arbiter can also release
        address arbiter = IArbitrationOperator(paymentInfo.operator).ARBITER();
        return caller == arbiter;
    }
}
