// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {ArbitrationOperator} from "../../operator/arbitration/ArbitrationOperator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {NotPayer} from "./types/Errors.sol";
import {PayerBypassTriggered} from "./types/Events.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title PayerBypassCondition
 * @notice Abstract base contract for release conditions that support payer bypass.
 *         Allows the payer to waive the release condition and allow immediate release.
 */
abstract contract PayerBypassCondition is ERC165 {
    /// @notice Tracks which payments have been bypassed by the payer
    /// @dev Key: paymentInfoHash
    mapping(bytes32 => bool) public payerBypassed;

    /**
     * @notice Payer bypasses the release condition to allow immediate release
     * @param paymentInfo PaymentInfo struct from the operator
     * @dev Only the payer of the payment can call this
     */
    function payerBypass(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external virtual {
        if (msg.sender != paymentInfo.payer) revert NotPayer();

        bytes32 paymentInfoHash = _getHash(paymentInfo);
        payerBypassed[paymentInfoHash] = true;

        emit PayerBypassTriggered(paymentInfo, msg.sender);
    }

    /**
     * @notice Check if a payment has been bypassed by the payer
     * @param paymentInfo PaymentInfo struct
     * @return True if the payer has bypassed the release condition
     */
    function isPayerBypassed(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) public view virtual returns (bool) {
        return payerBypassed[_getHash(paymentInfo)];
    }

    /**
     * @notice Internal helper to compute hash from PaymentInfo
     * @dev Uses the operator's escrow to compute the canonical hash
     */
    function _getHash(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) internal view virtual returns (bytes32) {
        return ArbitrationOperator(paymentInfo.operator).ESCROW().getHash(paymentInfo);
    }

    /**
     * @inheritdoc ERC165
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
