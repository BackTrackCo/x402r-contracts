// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IReleaseCondition} from "../../operator/types/IReleaseCondition.sol";
import {IAuthorizable} from "../../operator/types/IAuthorizable.sol";
import {ArbitrationOperator} from "../../operator/arbitration/ArbitrationOperator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {
    InvalidEscrowPeriod,
    ReleaseLocked,
    FundsFrozen,
    EscrowPeriodExpired,
    UnauthorizedFreeze,
    AlreadyFrozen,
    NotFrozen,
    NoFreezePolicy
} from "./types/Errors.sol";
import {IFreezePolicy} from "./types/IFreezePolicy.sol";
import {PaymentAuthorized, PaymentFrozen, PaymentUnfrozen} from "./types/Events.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title EscrowPeriodCondition
 * @notice Release condition that enforces a time-based escrow period before funds can be released.
 *         Payer can bypass this by calling operator.release() directly.
 *         Supports freeze/unfreeze with optional policy-based authorization.
 *
 * @dev Key features:
 *      - Operator-agnostic: works with any ArbitrationOperator
 *      - Funds locked for ESCROW_PERIOD seconds after authorization
 *      - Freeze state owned by this contract, policy determines who can freeze/unfreeze
 *      - Freezing only allowed during escrow period, but frozen state persists
 *      - Payer can always bypass by calling operator.release() directly
 *      - Users call authorize() on this contract, which forwards to operator and tracks time
 */
contract EscrowPeriodCondition is IReleaseCondition, IAuthorizable, ERC165 {
    /// @notice Duration of the escrow period in seconds
    uint256 public immutable ESCROW_PERIOD;

    /// @notice Optional freeze policy contract (address(0) = no freeze support)
    IFreezePolicy public immutable FREEZE_POLICY;

    /// @notice Stores the authorization time for each payment
    /// @dev Key: paymentInfoHash
    mapping(bytes32 => uint256) public authorizationTimes;

    /// @notice Tracks frozen payments
    /// @dev Key: paymentInfoHash
    mapping(bytes32 => bool) public frozen;

    constructor(uint256 _escrowPeriod, address _freezePolicy) {
        if (_escrowPeriod == 0) revert InvalidEscrowPeriod();
        ESCROW_PERIOD = _escrowPeriod;
        FREEZE_POLICY = IFreezePolicy(_freezePolicy);
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

        emit PaymentAuthorized(paymentInfo, block.timestamp);
    }

    /**
     * @notice Freeze a payment to block release
     * @dev Only callable during escrow period. Authorization checked via FREEZE_POLICY.
     * @param paymentInfo PaymentInfo struct for the payment to freeze
     */
    function freeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        if (address(FREEZE_POLICY) == address(0)) revert NoFreezePolicy();

        ArbitrationOperator operator = ArbitrationOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);

        // Check escrow period hasn't expired
        uint256 authTime = authorizationTimes[paymentInfoHash];
        if (authTime == 0 || block.timestamp >= authTime + ESCROW_PERIOD) {
            revert EscrowPeriodExpired();
        }

        // Check authorization via policy
        if (!FREEZE_POLICY.canFreeze(paymentInfo, msg.sender)) {
            revert UnauthorizedFreeze();
        }

        if (frozen[paymentInfoHash]) revert AlreadyFrozen();

        frozen[paymentInfoHash] = true;

        emit PaymentFrozen(paymentInfo, msg.sender);
    }

    /**
     * @notice Unfreeze a payment to allow release
     * @dev No escrow period check - unfreezing should always be allowed.
     *      Authorization checked via FREEZE_POLICY.
     * @param paymentInfo PaymentInfo struct for the payment to unfreeze
     */
    function unfreeze(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external {
        if (address(FREEZE_POLICY) == address(0)) revert NoFreezePolicy();

        ArbitrationOperator operator = ArbitrationOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);

        // Check authorization via policy
        if (!FREEZE_POLICY.canUnfreeze(paymentInfo, msg.sender)) {
            revert UnauthorizedFreeze();
        }

        if (!frozen[paymentInfoHash]) revert NotFrozen();

        frozen[paymentInfoHash] = false;

        emit PaymentUnfrozen(paymentInfo, msg.sender);
    }

    /**
     * @notice Release funds by calling the operator
     * @dev Anyone can call after escrow period has passed and funds are not frozen.
     *      Note: Payer can bypass this by calling operator.release() directly.
     * @param paymentInfo PaymentInfo struct
     * @param amount Amount to release
     */
    function release(
        AuthCaptureEscrow.PaymentInfo calldata paymentInfo,
        uint256 amount
    ) external override {
        ArbitrationOperator operator = ArbitrationOperator(paymentInfo.operator);
        bytes32 paymentInfoHash = operator.ESCROW().getHash(paymentInfo);

        // Check if frozen
        if (frozen[paymentInfoHash]) {
            revert FundsFrozen();
        }

        // Check if payment was authorized through this contract
        uint256 authTime = authorizationTimes[paymentInfoHash];
        if (authTime == 0) {
            revert ReleaseLocked(); // Not authorized through this contract
        }

        // Check if escrow period has passed since authorization
        if (block.timestamp < authTime + ESCROW_PERIOD) {
            revert ReleaseLocked();
        }

        operator.release(paymentInfo, amount);
    }

    /**
     * @notice Get the authorization time for a payment
     * @param paymentInfo PaymentInfo struct
     * @return The timestamp when the payment was authorized (0 if not authorized through this contract)
     */
    function getAuthorizationTime(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (uint256) {
        return authorizationTimes[ArbitrationOperator(paymentInfo.operator).ESCROW().getHash(paymentInfo)];
    }

    /**
     * @notice Check if a payment is frozen
     * @param paymentInfo PaymentInfo struct
     * @return True if the payment is frozen
     */
    function isFrozen(AuthCaptureEscrow.PaymentInfo calldata paymentInfo) external view returns (bool) {
        return frozen[ArbitrationOperator(paymentInfo.operator).ESCROW().getHash(paymentInfo)];
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
