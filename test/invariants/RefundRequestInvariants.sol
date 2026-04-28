// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {ProtocolFeeConfig} from "../../src/plugins/fees/ProtocolFeeConfig.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {ICondition} from "../../src/plugins/conditions/ICondition.sol";
import {StaticAddressCondition} from "../../src/plugins/conditions/access/static-address/StaticAddressCondition.sol";
import {ReceiverCondition} from "../../src/plugins/conditions/access/ReceiverCondition.sol";
import {PayerCondition} from "../../src/plugins/conditions/access/PayerCondition.sol";
import {OrCondition} from "../../src/plugins/conditions/combinators/OrCondition.sol";
import {RefundRequest} from "../../src/requests/refund/RefundRequest.sol";
import {RequestStatus} from "../../src/requests/types/Types.sol";

/**
 * @title RefundRequestInvariants
 * @notice Echidna property-based testing for RefundRequest state machine.
 * @dev Verifies that Approved, Denied, and Refused are terminal states, and only
 *      Pending requests can transition to new states.
 *
 * Key design: Cancelled allows re-request (not terminal), Approved/Denied/Refused are terminal.
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

    address public arbiter = address(0x3000);
    address public payer = address(0x1000);
    address public receiver = address(0x2000);

    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    // Ghost state for invariant checking
    bytes32[] public trackedKeys; // paymentInfoHashes
    mapping(bytes32 => bool) public wasTerminallyResolved; // Approved, Denied, or Refused
    mapping(bytes32 => RequestStatus) public lastKnownStatus;
    mapping(bytes32 => AuthCaptureEscrow.PaymentInfo) private trackedPaymentInfos;
    uint256 public nextSalt;

    constructor() {
        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        ProtocolFeeConfig protocolFeeConfig = new ProtocolFeeConfig(address(0), address(this), address(this));

        refundRequest = new RefundRequest(arbiter);

        // Build VOID_CONDITION = Or(StaticAddressCondition(arbiter), ReceiverCondition)
        StaticAddressCondition arbiterCondition = new StaticAddressCondition(arbiter);
        ReceiverCondition receiverCondition = new ReceiverCondition();
        ICondition[] memory refundConditions = new ICondition[](2);
        refundConditions[0] = ICondition(address(arbiterCondition));
        refundConditions[1] = ICondition(address(receiverCondition));
        OrCondition voidCondition = new OrCondition(refundConditions);

        // Build CAPTURE_CONDITION = Or(StaticAddressCondition(arbiter), PayerCondition)
        PayerCondition payerCondition = new PayerCondition();
        ICondition[] memory captureConditions = new ICondition[](2);
        captureConditions[0] = ICondition(address(arbiterCondition));
        captureConditions[1] = ICondition(address(payerCondition));
        OrCondition captureCondition = new OrCondition(captureConditions);

        PaymentOperatorFactory operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeReceiver: address(this),
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            captureCondition: address(captureCondition),
            captureRecorder: address(0),
            voidCondition: address(voidCondition),
            voidRecorder: address(refundRequest),
            refundCondition: address(0),
            refundRecorder: address(0)
        });
        operator = PaymentOperator(operatorFactory.deployOperator(config));

        token.mint(payer, PAYMENT_AMOUNT * 100);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
    }

    // ============ Fuzzing Entry Points ============

    function requestRefund_fuzz(uint120 amount, uint256 salt) public {
        if (amount == 0 || amount > 10_000_000 * 10 ** 18) return;

        nextSalt++;

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
        try refundRequest.requestRefund(paymentInfo, amount) {
            bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

            trackedKeys.push(paymentInfoHash);
            lastKnownStatus[paymentInfoHash] = RequestStatus.Pending;
            trackedPaymentInfos[paymentInfoHash] = paymentInfo;
        } catch {}
    }

    function approveRefund_fuzz(uint256 keyIndex) public {
        if (trackedKeys.length == 0) return;
        uint256 index = keyIndex % trackedKeys.length;
        bytes32 paymentInfoHash = trackedKeys[index];

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = trackedPaymentInfos[paymentInfoHash];

        RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequestByKey(paymentInfoHash);

        // Arbiter calls operator.void() which triggers record()
        vm.prank(arbiter);
        try operator.void(paymentInfo, "") {
            lastKnownStatus[paymentInfoHash] = RequestStatus.Approved;
            wasTerminallyResolved[paymentInfoHash] = true;
        } catch {}
    }

    function denyRefund_fuzz(uint256 keyIndex) public {
        if (trackedKeys.length == 0) return;
        uint256 index = keyIndex % trackedKeys.length;
        bytes32 paymentInfoHash = trackedKeys[index];

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = trackedPaymentInfos[paymentInfoHash];

        vm.prank(arbiter);
        try refundRequest.deny(paymentInfo) {
            lastKnownStatus[paymentInfoHash] = RequestStatus.Denied;
            wasTerminallyResolved[paymentInfoHash] = true;
        } catch {}
    }

    function refuseRefund_fuzz(uint256 keyIndex) public {
        if (trackedKeys.length == 0) return;
        uint256 index = keyIndex % trackedKeys.length;
        bytes32 paymentInfoHash = trackedKeys[index];

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = trackedPaymentInfos[paymentInfoHash];

        vm.prank(arbiter);
        try refundRequest.refuse(paymentInfo) {
            lastKnownStatus[paymentInfoHash] = RequestStatus.Refused;
            wasTerminallyResolved[paymentInfoHash] = true;
        } catch {}
    }

    function cancelRefund_fuzz(uint256 keyIndex) public {
        if (trackedKeys.length == 0) return;
        uint256 index = keyIndex % trackedKeys.length;
        bytes32 paymentInfoHash = trackedKeys[index];

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = trackedPaymentInfos[paymentInfoHash];

        vm.prank(payer);
        try refundRequest.cancelRefundRequest(paymentInfo) {
            lastKnownStatus[paymentInfoHash] = RequestStatus.Cancelled;
        } catch {}
    }

    // ============ Echidna Invariants ============

    /// @notice Once Approved, a request cannot change state
    function echidna_approved_is_terminal() public view returns (bool) {
        for (uint256 i = 0; i < trackedKeys.length; i++) {
            bytes32 key = trackedKeys[i];
            if (lastKnownStatus[key] == RequestStatus.Approved) {
                RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequestByKey(key);
                if (data.status != RequestStatus.Approved) {
                    return false;
                }
            }
        }
        return true;
    }

    /// @notice Once Denied, a request cannot change state
    function echidna_denied_is_terminal() public view returns (bool) {
        for (uint256 i = 0; i < trackedKeys.length; i++) {
            bytes32 key = trackedKeys[i];
            if (lastKnownStatus[key] == RequestStatus.Denied) {
                RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequestByKey(key);
                if (data.status != RequestStatus.Denied) {
                    return false;
                }
            }
        }
        return true;
    }

    /// @notice Once Refused, a request cannot change state
    function echidna_refused_is_terminal() public view returns (bool) {
        for (uint256 i = 0; i < trackedKeys.length; i++) {
            bytes32 key = trackedKeys[i];
            if (lastKnownStatus[key] == RequestStatus.Refused) {
                RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequestByKey(key);
                if (data.status != RequestStatus.Refused) {
                    return false;
                }
            }
        }
        return true;
    }

    /// @notice Only Pending requests can transition (except Cancelled -> Pending via re-request)
    function echidna_only_pending_can_transition() public view returns (bool) {
        for (uint256 i = 0; i < trackedKeys.length; i++) {
            bytes32 key = trackedKeys[i];
            if (wasTerminallyResolved[key]) {
                RefundRequest.RefundRequestData memory data = refundRequest.getRefundRequestByKey(key);
                RequestStatus onChainStatus = data.status;
                if (
                    onChainStatus != RequestStatus.Approved && onChainStatus != RequestStatus.Denied
                        && onChainStatus != RequestStatus.Refused
                ) {
                    return false;
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
