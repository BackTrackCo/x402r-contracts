// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title IOperator
 * @notice Interface for operator contracts that manage payment authorization and release
 * @dev Operators are the intermediary between conditions and the escrow contract.
 *      They handle the business logic for payment flows while delegating fund custody to escrow.
 *
 *      Typical flow:
 *        User -> ICondition.check() -> IOperator.release() -> Escrow.capture()
 *        User -> IOperator.authorize() -> Escrow.authorize()
 */
interface IOperator {
    /**
     * @notice Get the escrow contract address
     * @return The AuthCaptureEscrow contract address
     */
    function ESCROW() external view returns (AuthCaptureEscrow);
    /**
     * @notice Authorize a payment through the escrow
     * @param paymentInfo PaymentInfo struct with payment details
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

    /**
     * @notice Release funds to the receiver
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to release
     */
    function release(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint256 amount) external;

    /**
     * @notice Refund funds while still in escrow (before capture)
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to return to payer
     */
    function refundInEscrow(AuthCaptureEscrow.PaymentInfo calldata paymentInfo, uint120 amount) external;

    /**
     * @notice Refund captured funds back to payer (after capture/release)
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to refund to payer
     * @param tokenCollector Address of the token collector that will source the refund
     * @param collectorData Data to pass to the token collector
     */
    function refundPostEscrow(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external;
}
