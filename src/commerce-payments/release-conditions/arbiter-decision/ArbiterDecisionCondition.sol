// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IReleaseCondition} from "../../operator/types/IReleaseCondition.sol";
import {ArbitrationOperator} from "../../operator/arbitration/ArbitrationOperator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {NotArbiter} from "./types/Errors.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title ArbiterDecisionCondition
 * @notice Release condition where only the arbiter can release funds via this contract.
 *         Payer can bypass by calling operator.release() directly.
 */
contract ArbiterDecisionCondition is IReleaseCondition, ERC165 {
    /**
     * @notice Release funds by calling the operator
     * @dev Only arbiter can call this. Payer can bypass by calling operator.release() directly.
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to release
     */
    function release(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount
    ) external override {
        if (msg.sender != ArbitrationOperator(paymentInfo.operator).ARBITER()) {
            revert NotArbiter();
        }

        ArbitrationOperator(paymentInfo.operator).release(paymentInfo, amount);
    }

    /**
     * @notice Checks if the contract supports an interface
     * @param interfaceId The interface ID to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IReleaseCondition).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
