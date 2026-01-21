// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IReleaseCondition} from "../../operator/types/IReleaseCondition.sol";
import {IAuthorizable} from "../../operator/types/IAuthorizable.sol";
import {ArbitrationOperator} from "../../operator/arbitration/ArbitrationOperator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PayerBypassCondition} from "../shared/PayerBypassCondition.sol";
import {InvalidEscrowPeriod} from "./types/Errors.sol";
import {PaymentAuthorized} from "./types/Events.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

// Note: Removing explicit NotPayer import as it is used by base, but if used here, valid. But logic removed so mostly likely unused here.
// Actually, check if used? payerBypass removed.
// We still need to import ERC165 if we use it explicitly?
// Base inherits ERC165. We inherit Base.
// But we still use `block.timestamp` etc.

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
contract EscrowPeriodCondition is IReleaseCondition, IAuthorizable, PayerBypassCondition {
    /// @notice Duration of the escrow period in seconds
    uint256 public immutable ESCROW_PERIOD;

    /// @notice Stores the authorization time for each payment
    /// @dev Key: paymentInfoHash
    mapping(bytes32 => uint256) public authorizationTimes;

    constructor(uint256 _escrowPeriod) {
        if (_escrowPeriod == 0) revert InvalidEscrowPeriod();
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
        bytes32 paymentInfoHash = _getHash(paymentInfo);
        authorizationTimes[paymentInfoHash] = block.timestamp;

        emit PaymentAuthorized(paymentInfo, block.timestamp);
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
        
        // If payer has bypassed, allow release immediately
        if (isPayerBypassed(paymentInfo)) {
            return true;
        }

        bytes32 paymentInfoHash = _getHash(paymentInfo);

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
     * @notice Checks if the contract supports an interface
     * @param interfaceId The interface ID to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(PayerBypassCondition) returns (bool) {
        return
            interfaceId == type(IReleaseCondition).interfaceId ||
            interfaceId == type(IAuthorizable).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
