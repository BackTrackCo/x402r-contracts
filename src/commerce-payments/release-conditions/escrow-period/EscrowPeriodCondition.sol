// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IReleaseCondition} from "../../operator/types/IReleaseCondition.sol";
import {IAuthorizable} from "../../operator/types/IAuthorizable.sol";
import {ArbitrationOperator} from "../../operator/arbitration/ArbitrationOperator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {NotPayer} from "./types/Errors.sol";
import {PayerBypassTriggered, PaymentAuthorized} from "./types/Events.sol";

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title EscrowPeriodCondition
 * @notice Release condition that enforces a time-based escrow period before funds can be released.
 *         The payer can optionally bypass the escrow period to allow immediate release.
 *
 * @dev Key features:
 *      - Operator-agnostic: works with any ArbitrationOperator
 *      - Funds locked for ESCROW_PERIOD seconds after authorization
 *      - Payer can call payerBypass() to waive the wait and allow immediate release
 *      - Users call authorize() on this contract, which forwards to operator and tracks time
 */
contract EscrowPeriodCondition is IReleaseCondition, IAuthorizable, ERC165 {
    /// @notice Duration of the escrow period in seconds
    uint256 public immutable ESCROW_PERIOD;

    /// @notice Stores the authorization time for each payment
    /// @dev Key: paymentInfoHash
    mapping(bytes32 => uint256) public authorizationTimes;

    /// @notice Tracks which payments have been bypassed by the payer
    /// @dev Key: paymentInfoHash
    mapping(bytes32 => bool) public payerBypassed;

    constructor(uint256 _escrowPeriod) {
        ESCROW_PERIOD = _escrowPeriod;
    }

    /**
     * @notice Authorize payment through the operator, tracking authorization time
     * @dev Forwards to paymentInfo.operator.authorize() and records block.timestamp
     * @param paymentInfo PaymentInfo struct (must have correct required values for operator)
     * @param amount Amount to authorize
     * @param tokenCollector Address of the token collector
     * @param collectorData Data to pass to the token collector
     */
    function authorize(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount,
        address tokenCollector,
        bytes calldata collectorData
    ) external override {
        ArbitrationOperator operator = ArbitrationOperator(paymentInfo.operator);

        // Forward to operator (operator validates paymentInfo)
        operator.authorize(paymentInfo, amount, tokenCollector, collectorData);

        // Compute hash and track authorization time
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);
        authorizationTimes[paymentInfoHash] = block.timestamp;

        emit PaymentAuthorized(paymentInfoHash, block.timestamp);
    }

    /**
     * @notice Payer bypasses the escrow period to allow immediate release
     * @param paymentInfo PaymentInfo struct from the operator
     * @dev Only the payer of the payment can call this
     */
    function payerBypass(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        if (msg.sender != paymentInfo.payer) revert NotPayer();

        bytes32 paymentInfoHash = _getHash(paymentInfo);
        payerBypassed[paymentInfoHash] = true;

        emit PayerBypassTriggered(paymentInfoHash, msg.sender);
    }

    /**
     * @notice Check if a payment can be released (called by ArbitrationOperator)
     * @param paymentInfo The PaymentInfo struct
     * @return True if escrow period has passed OR payer has bypassed
     */
    function canRelease(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 /* amount */
    ) external view override returns (bool) {

        bytes32 paymentInfoHash = _getHash(paymentInfo);

        // If payer has bypassed, allow release immediately
        if (payerBypassed[paymentInfoHash]) {
            return true;
        }

        // Check if payment was authorized through this contract
        uint256 authTime = authorizationTimes[paymentInfoHash];
        if (authTime == 0) {
            return false; // Not authorized through this contract
        }

        // Check if escrow period has passed since authorization
        return block.timestamp >= authTime + ESCROW_PERIOD;
    }

    /**
     * @notice Get the authorization time for a payment
     * @param paymentInfo PaymentInfo struct
     * @return The timestamp when the payment was authorized (0 if not authorized through this contract)
     */
    function getAuthorizationTime(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (uint256) {
        return authorizationTimes[_getHash(paymentInfo)];
    }

    /**
     * @notice Check if a payment has been bypassed by the payer
     * @param paymentInfo PaymentInfo struct
     * @return True if the payer has bypassed the escrow period
     */
    function isPayerBypassed(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (bool) {
        return payerBypassed[_getHash(paymentInfo)];
    }

    /**
     * @notice Internal helper to compute hash from PaymentInfo
     * @dev Uses the operator's escrow to compute the canonical hash
     */
    function _getHash(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) internal view returns (bytes32) {
        return ArbitrationOperator(paymentInfo.operator).ESCROW().getHash(paymentInfo);
    }

    /**
     * @notice Checks if the contract supports an interface
     * @param interfaceId The interface ID to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IReleaseCondition).interfaceId ||
            interfaceId == type(IAuthorizable).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
