// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IReleaseCondition} from "../../operator/types/IReleaseCondition.sol";
import {ArbitrationOperator} from "../../operator/arbitration/ArbitrationOperator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PayerBypassCondition} from "../shared/PayerBypassCondition.sol";
import {NotArbiter} from "./types/Errors.sol";
import {ArbiterApproved} from "./types/Events.sol";

/**
 * @title ArbiterDecisionCondition
 * @notice Release condition that requires explicit approval from the arbiter.
 *         The payer can also bypass this condition to allow immediate release.
 */
contract ArbiterDecisionCondition is IReleaseCondition, PayerBypassCondition {
    /// @notice Tracks which payments have been approved by the arbiter
    /// @dev Key: paymentInfoHash
    mapping(bytes32 => bool) public isApproved;


    /**
     * @notice Arbiter approves the release of funds
     * @param paymentInfo The PaymentInfo struct
     * @dev Only the arbiter of the payment can call this
     */
    function arbiterApprove(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        if (msg.sender != ArbitrationOperator(paymentInfo.operator).ARBITER()) revert NotArbiter();

        bytes32 paymentInfoHash = _getHash(paymentInfo);
        isApproved[paymentInfoHash] = true;

        emit ArbiterApproved(paymentInfo, msg.sender);
    }

    /**
     * @notice Check if a payment can be released
     * @param paymentInfo The PaymentInfo struct
     * @return True if arbiter has approved OR payer has bypassed
     */
    function canRelease(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 /* amount */
    ) external view override returns (bool) {
        bytes32 paymentInfoHash = _getHash(paymentInfo);
        
        // Return true if authorized (approved) by arbiter OR bypassed by payer
        return isApproved[paymentInfoHash] || isPayerBypassed(paymentInfo);
    }

    /**
     * @notice Checks if the contract supports an interface
     * @param interfaceId The interface ID to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(PayerBypassCondition) returns (bool) {
        return
            interfaceId == type(IReleaseCondition).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
