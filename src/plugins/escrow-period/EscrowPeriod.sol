// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {AuthorizationTimeRecorder} from "../recorders/AuthorizationTimeRecorder.sol";
import {ICondition} from "../conditions/ICondition.sol";
import {InvalidEscrowPeriod} from "./types/Errors.sol";

/**
 * @title EscrowPeriod
 * @notice Combined escrow period recorder and condition. Extends AuthorizationTimeRecorder
 *         with escrow period enforcement and ICondition implementation.
 *
 * @dev Implements both IRecorder (via AuthorizationTimeRecorder inheritance) and ICondition.
 *      Use the same address for both the AUTHORIZE_RECORDER and RELEASE_CONDITION slots
 *      on PaymentOperator.
 *
 *      For freeze functionality, deploy a separate Freeze condition contract and compose
 *      both via AndCondition([escrowPeriod, freeze]).
 *
 * TRUST ASSUMPTIONS:
 *      - Timestamp: Uses block.timestamp for time-based escrow periods.
 */
contract EscrowPeriod is AuthorizationTimeRecorder, ICondition {
    /// @notice Duration of the escrow period in seconds
    uint256 public immutable ESCROW_PERIOD;

    constructor(uint256 _escrowPeriod, address _escrow, bytes32 _authorizedCodehash)
        AuthorizationTimeRecorder(_escrow, _authorizedCodehash)
    {
        if (_escrowPeriod == 0) revert InvalidEscrowPeriod();
        ESCROW_PERIOD = _escrowPeriod;
    }

    // Note: record() inherited from AuthorizationTimeRecorder

    // ============ ICondition Implementation ============

    /**
     * @notice Check if funds can be released (escrow period passed)
     * @param paymentInfo PaymentInfo struct
     * @return allowed True if escrow period has passed (and payment is authorized)
     */
    function check(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256, address)
        external
        view
        override(ICondition)
        returns (bool allowed)
    {
        return !isDuringEscrowPeriod(paymentInfo);
    }

    // ============ View Functions ============

    // Note: getAuthorizationTime() inherited from AuthorizationTimeRecorder

    /**
     * @notice Check if a payment is currently within its escrow period
     * @dev Returns true when authTime != 0 && block.timestamp < authTime + ESCROW_PERIOD.
     *      Returns false when not authorized (authTime == 0) or escrow period has passed.
     *      Used by the Freeze contract to restrict freezing to during the escrow period.
     * @param paymentInfo PaymentInfo struct
     * @return True if the payment is authorized and within the escrow period
     */
    function isDuringEscrowPeriod(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) public view returns (bool) {
        bytes32 paymentInfoHash = _getPaymentHash(paymentInfo);
        uint256 authTime = authorizationTimes[paymentInfoHash];
        if (authTime == 0) {
            return false;
        }
        return block.timestamp < authTime + ESCROW_PERIOD;
    }
}
