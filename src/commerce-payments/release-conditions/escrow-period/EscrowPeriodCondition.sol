// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {IReleaseCondition} from "../../operator/types/IReleaseCondition.sol";
import {IAuthorizable} from "../../operator/types/IAuthorizable.sol";
import {ArbitrationOperator} from "../../operator/arbitration/ArbitrationOperator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {InvalidEscrowPeriod, ReleaseLocked, FundsFrozen} from "./types/Errors.sol";
import {IFreezeChecker} from "./types/IFreezeChecker.sol";
import {PaymentAuthorized} from "./types/Events.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title EscrowPeriodCondition
 * @notice Release condition that enforces a time-based escrow period before funds can be released.
 *         Payer can bypass this by calling operator.release() directly.
 *         Optionally supports freeze checks for arbitration.
 *
 * @dev Key features:
 *      - Operator-agnostic: works with any ArbitrationOperator
 *      - Funds locked for ESCROW_PERIOD seconds after authorization
 *      - Optional freeze checker blocks release during arbitration
 *      - Payer can always bypass by calling operator.release() directly
 *      - Users call authorize() on this contract, which forwards to operator and tracks time
 */
contract EscrowPeriodCondition is IReleaseCondition, IAuthorizable, ERC165 {
    /// @notice Duration of the escrow period in seconds
    uint256 public immutable ESCROW_PERIOD;

    /// @notice Optional freeze checker contract (address(0) = no freeze check)
    IFreezeChecker public immutable FREEZE_CHECKER;

    /// @notice Stores the authorization time for each payment
    /// @dev Key: paymentInfoHash
    mapping(bytes32 => uint256) public authorizationTimes;

    constructor(uint256 _escrowPeriod, address _freezeChecker) {
        if (_escrowPeriod == 0) revert InvalidEscrowPeriod();
        ESCROW_PERIOD = _escrowPeriod;
        FREEZE_CHECKER = IFreezeChecker(_freezeChecker);
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

        // Check if frozen by external contract (e.g., during arbitration)
        if (address(FREEZE_CHECKER) != address(0) && FREEZE_CHECKER.isFrozen(paymentInfoHash)) {
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
