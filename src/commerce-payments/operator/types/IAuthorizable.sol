// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title IAuthorizable
 * @notice Interface for contracts that can authorize payments
 * @dev Implement this interface to create contracts that route authorizations
 *      through an ArbitrationOperator. The paymentInfo.operator field determines
 *      which operator handles the authorization.
 */
interface IAuthorizable {
    /**
     * @notice Authorize a payment via the operator specified in paymentInfo
     * @param paymentInfo PaymentInfo struct (paymentInfo.operator determines the target)
     * @param amount Amount to authorize
     * @param tokenCollector Address of the token collector
     * @param collectorData Data to pass to the token collector
     */
    function authorize(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external;
}
