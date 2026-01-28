// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../../../src/operator/payment/PaymentOperator.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

/**
 * @title PaymentOperatorHandler
 * @notice Handler contract for Foundry invariant testing of PaymentOperator.
 *         Wraps all state-mutating operations with try/catch and ghost variable tracking.
 */
contract PaymentOperatorHandler is Test {
    PaymentOperator public operator;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;

    address public payer;
    address public receiver;

    // Ghost variables for invariant checking
    uint256 public ghost_totalAuthorized;
    uint256 public ghost_totalReleased;
    uint256 public ghost_totalRefunded;
    uint256 public ghost_totalDistributed;

    // Track payments for invariant assertions
    bytes32[] public ghost_paymentHashes;
    mapping(bytes32 => uint256) public ghost_authorizedAmounts;
    mapping(bytes32 => uint256) public ghost_capturedAmounts;
    mapping(bytes32 => uint256) public ghost_refundedAmounts;
    mapping(bytes32 => AuthCaptureEscrow.PaymentInfo) public ghost_paymentInfos;

    uint256 public ghost_callCount_authorize;
    uint256 public ghost_callCount_release;
    uint256 public ghost_callCount_refund;
    uint256 public ghost_callCount_distribute;

    constructor(
        PaymentOperator _operator,
        AuthCaptureEscrow _escrow,
        PreApprovalPaymentCollector _collector,
        MockERC20 _token,
        address _payer,
        address _receiver
    ) {
        operator = _operator;
        escrow = _escrow;
        collector = _collector;
        token = _token;
        payer = _payer;
        receiver = _receiver;
    }

    function handler_authorize(uint120 amount, uint256 salt) external {
        amount = uint120(bound(amount, 1, 10_000_000 * 10 ** 18));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = AuthCaptureEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: amount,
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(operator),
            salt: salt
        });

        vm.startPrank(payer);
        collector.preApprove(paymentInfo);
        try operator.authorize(paymentInfo, amount, address(collector), "") {
            bytes32 hash = escrow.getHash(paymentInfo);
            ghost_paymentHashes.push(hash);
            ghost_authorizedAmounts[hash] = amount;
            ghost_paymentInfos[hash] = paymentInfo;
            ghost_totalAuthorized += amount;
            ghost_callCount_authorize++;
        } catch {}
        vm.stopPrank();
    }

    function handler_release(uint256 paymentIndex, uint120 amount) external {
        if (ghost_paymentHashes.length == 0) return;

        uint256 index = paymentIndex % ghost_paymentHashes.length;
        bytes32 hash = ghost_paymentHashes[index];
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = ghost_paymentInfos[hash];

        (, uint120 capturable,) = escrow.paymentState(hash);
        if (capturable == 0) return;
        amount = uint120(bound(amount, 1, capturable));

        try operator.release(paymentInfo, amount) {
            ghost_capturedAmounts[hash] += amount;
            ghost_totalReleased += amount;
            ghost_callCount_release++;
        } catch {}
    }

    function handler_refundInEscrow(uint256 paymentIndex, uint120 amount) external {
        if (ghost_paymentHashes.length == 0) return;

        uint256 index = paymentIndex % ghost_paymentHashes.length;
        bytes32 hash = ghost_paymentHashes[index];
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = ghost_paymentInfos[hash];

        (, uint120 capturable,) = escrow.paymentState(hash);
        if (capturable == 0) return;
        amount = uint120(bound(amount, 1, capturable));

        try operator.refundInEscrow(paymentInfo, amount) {
            ghost_refundedAmounts[hash] += amount;
            ghost_totalRefunded += amount;
            ghost_callCount_refund++;
        } catch {}
    }

    function handler_distributeFees() external {
        try operator.distributeFees(address(token)) {
            ghost_callCount_distribute++;
        } catch {}
    }

    function handler_warpTime(uint256 delta) external {
        delta = bound(delta, 1, 30 days);
        vm.warp(block.timestamp + delta);
    }

    // ============ View Helpers ============

    function ghost_paymentHashCount() external view returns (uint256) {
        return ghost_paymentHashes.length;
    }
}
