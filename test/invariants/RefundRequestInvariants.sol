// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {ProtocolFeeConfig} from "../../src/plugins/fees/ProtocolFeeConfig.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {RefundRequest} from "../../src/requests/refund/RefundRequest.sol";
import {RequestStatus} from "../../src/requests/types/Types.sol";

/**
 * @title RefundRequestInvariants
 * @notice Echidna property-based testing for RefundRequest state machine.
 * @dev Verifies that Approved and Denied are terminal states, and only
 *      Pending requests can transition to new states.
 *
 * Key design: Cancelled allows re-request (not terminal), Approved/Denied are terminal.
 *
 * Usage:
 *   echidna . --contract RefundRequestInvariants --config echidna.yaml
 */
contract RefundRequestInvariants is Test {
    PaymentOperator public operator;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;
    RefundRequest public refundRequest;

    address public payer = address(0x1000);
    address public receiver = address(0x2000);

    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    // Ghost state for invariant checking
    bytes32[] public trackedKeys; // compositeKeys
    mapping(bytes32 => bool) public wasTerminallyResolved; // Approved or Denied
    mapping(bytes32 => RequestStatus) public lastKnownStatus;
    mapping(bytes32 => AuthCaptureEscrow.PaymentInfo) private trackedPaymentInfos;
    mapping(bytes32 => uint256) private trackedNonces;
    uint256 public nextSalt;

    constructor() {
        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        ProtocolFeeConfig protocolFeeConfig = new ProtocolFeeConfig(address(0), address(this), address(this));
        PaymentOperatorFactory operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: address(this),
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(0),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = PaymentOperator(operatorFactory.deployOperator(config));

        refundRequest = new RefundRequest();

        token.mint(payer, PAYMENT_AMOUNT * 100);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
    }

    // ============ Fuzzing Entry Points ============

    function requestRefund_fuzz(uint120 amount, uint256 salt) public {
        if (amount == 0 || amount > 10_000_000 * 10 ** 18) return;

        nextSalt++;
        uint256 nonce = 0;

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(nextSalt);

        // Authorize payment first
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        try operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "") {}
        catch {
            return;
        }

        // Request refund
        vm.prank(payer);
        try refundRequest.requestRefund(paymentInfo, amount, nonce) {
            bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
            bytes32 compositeKey = keccak256(abi.encodePacked(paymentInfoHash, nonce));

            trackedKeys.push(compositeKey);
            lastKnownStatus[compositeKey] = RequestStatus.Pending;
            trackedPaymentInfos[compositeKey] = paymentInfo;
            trackedNonces[compositeKey] = nonce;
        } catch {}
    }

    function approveRefund_fuzz(uint256 keyIndex) public {
        if (trackedKeys.length == 0) return;
        uint256 index = keyIndex % trackedKeys.length;
        bytes32 compositeKey = trackedKeys[index];

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = trackedPaymentInfos[compositeKey];
        uint256 nonce = trackedNonces[compositeKey];

        vm.prank(receiver);
        try refundRequest.updateStatus(paymentInfo, nonce, RequestStatus.Approved) {
            lastKnownStatus[compositeKey] = RequestStatus.Approved;
            wasTerminallyResolved[compositeKey] = true;
        } catch {}
    }

    function denyRefund_fuzz(uint256 keyIndex) public {
        if (trackedKeys.length == 0) return;
        uint256 index = keyIndex % trackedKeys.length;
        bytes32 compositeKey = trackedKeys[index];

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = trackedPaymentInfos[compositeKey];
        uint256 nonce = trackedNonces[compositeKey];

        vm.prank(receiver);
        try refundRequest.updateStatus(paymentInfo, nonce, RequestStatus.Denied) {
            lastKnownStatus[compositeKey] = RequestStatus.Denied;
            wasTerminallyResolved[compositeKey] = true;
        } catch {}
    }

    function cancelRefund_fuzz(uint256 keyIndex) public {
        if (trackedKeys.length == 0) return;
        uint256 index = keyIndex % trackedKeys.length;
        bytes32 compositeKey = trackedKeys[index];

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = trackedPaymentInfos[compositeKey];
        uint256 nonce = trackedNonces[compositeKey];

        vm.prank(payer);
        try refundRequest.cancelRefundRequest(paymentInfo, nonce) {
            lastKnownStatus[compositeKey] = RequestStatus.Cancelled;
        } catch {}
    }

    // ============ Echidna Invariants ============

    /// @notice Once Approved, a request cannot become Pending, Denied, or Cancelled
    function echidna_approved_is_terminal() public view returns (bool) {
        for (uint256 i = 0; i < trackedKeys.length; i++) {
            bytes32 key = trackedKeys[i];
            if (lastKnownStatus[key] == RequestStatus.Approved) {
                // If we recorded it as Approved, verify it's still Approved on-chain
                RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequestByKey(key);
                if (data.status != RequestStatus.Approved) {
                    return false; // Violation: terminal state changed
                }
            }
        }
        return true;
    }

    /// @notice Once Denied, a request cannot become Pending, Approved, or Cancelled
    function echidna_denied_is_terminal() public view returns (bool) {
        for (uint256 i = 0; i < trackedKeys.length; i++) {
            bytes32 key = trackedKeys[i];
            if (lastKnownStatus[key] == RequestStatus.Denied) {
                // If we recorded it as Denied, verify it's still Denied on-chain
                RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequestByKey(key);
                if (data.status != RequestStatus.Denied) {
                    return false; // Violation: terminal state changed
                }
            }
        }
        return true;
    }

    /// @notice Only Pending requests can transition (except Cancelled -> Pending via re-request)
    function echidna_only_pending_can_transition() public view returns (bool) {
        for (uint256 i = 0; i < trackedKeys.length; i++) {
            bytes32 key = trackedKeys[i];
            // If it was terminally resolved (Approved/Denied), it must stay that way
            if (wasTerminallyResolved[key]) {
                RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequestByKey(key);
                RequestStatus onChainStatus = data.status;
                if (onChainStatus != RequestStatus.Approved && onChainStatus != RequestStatus.Denied) {
                    return false; // Violation: terminal state reverted
                }
            }
        }
        return true;
    }

    // ============ Helpers ============

    function _createPaymentInfo(uint256 salt) internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 30 days),
            refundExpiry: uint48(block.timestamp + 60 days),
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(operator),
            salt: salt
        });
    }
}
