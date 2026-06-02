// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ProtocolFeeConfig} from "../src/plugins/fees/ProtocolFeeConfig.sol";
import {StaticFeeCalculator} from "../src/plugins/fees/static-fee-calculator/StaticFeeCalculator.sol";

/**
 * @title ContractPathDispatchTest
 * @notice Regression coverage for the auth-capture facilitator "contract-path", where a
 *         PaymentOperator is set as the captureAuthorizer and the facilitator forwards the
 *         *literal canonical escrow selector* to it (it encodes against the escrow ABI, not the
 *         operator ABI). This is the exact shape that broke when the operator exposed a 4-arg
 *         `charge` (selector 0x3d2c2d9d): the facilitator's 6-arg escrow `charge` (0x9e65819f)
 *         found no matching function, hit the fallback, and reverted.
 *
 *         These tests drive the operator the way the facilitator does — `abi.encodeCall` against
 *         the `AuthCaptureEscrow` function pointers (so the encoded selector is the escrow's) and a
 *         low-level call to the operator address — proving the operator can *receive* the forwarded
 *         calls, not merely that the facilitator *sends* them.
 */
contract ContractPathDispatchTest is Test {
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;

    ProtocolFeeConfig public protocolFeeConfig;
    PaymentOperatorFactory public factory;
    PaymentOperator public operator;

    address public owner;
    address public protocolFeeRecipient;
    address public operatorFeeRecipient;
    address public payer;
    address public receiver;
    // Stands in for the facilitator EOA that forwards the call to the contract captureAuthorizer.
    address public facilitator;

    uint256 public constant PROTOCOL_BPS = 30;
    uint256 public constant OPERATOR_BPS = 20;
    uint256 public constant TOTAL_BPS = PROTOCOL_BPS + OPERATOR_BPS;
    uint256 public constant PAYMENT_AMOUNT = 1_000_000;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        operatorFeeRecipient = makeAddr("operatorFeeRecipient");
        payer = makeAddr("payer");
        receiver = makeAddr("receiver");
        facilitator = makeAddr("facilitator");

        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        StaticFeeCalculator protocolCalc = new StaticFeeCalculator(PROTOCOL_BPS);
        protocolFeeConfig = new ProtocolFeeConfig(address(protocolCalc), protocolFeeRecipient, owner);

        factory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));
        StaticFeeCalculator operatorCalc = new StaticFeeCalculator(OPERATOR_BPS);
        operator = PaymentOperator(factory.deployOperator(_operatorConfig(address(operatorCalc))));

        token.mint(payer, 100_000_000 * 10 ** 18);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
    }

    /// @notice The operator's action entrypoints must share selectors with the canonical escrow,
    ///         so a facilitator encoding against the escrow ABI dispatches into the operator.
    function test_OperatorSelectors_MatchCanonicalEscrow() public pure {
        assertEq(
            PaymentOperator.charge.selector,
            AuthCaptureEscrow.charge.selector,
            "operator charge selector must equal escrow charge selector"
        );
        assertEq(
            PaymentOperator.authorize.selector,
            AuthCaptureEscrow.authorize.selector,
            "operator authorize selector must equal escrow authorize selector"
        );
    }

    /// @notice autoCapture contract-path: facilitator forwards the escrow's 6-arg `charge` to the
    ///         operator. Before the fix this reverted (no matching selector → fallback).
    function test_ContractPath_ChargeDispatchesViaEscrowSelector() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _paymentInfo();

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        // Exactly how the facilitator builds the contract-path call: encode against the escrow
        // function (escrow selector + 6 args) and send it to the captureAuthorizer contract.
        bytes memory data = abi.encodeCall(
            AuthCaptureEscrow.charge,
            (
                paymentInfo,
                PAYMENT_AMOUNT,
                address(collector),
                "",
                uint16(paymentInfo.minFeeBps),
                paymentInfo.feeReceiver
            )
        );

        uint256 receiverBefore = token.balanceOf(receiver);

        vm.prank(facilitator);
        (bool ok,) = address(operator).call(data);
        assertTrue(ok, "forwarded escrow charge selector must dispatch into the operator");

        // Funds went straight to receiver (net of fees) and protocol fees were recomputed internally.
        uint256 expectedTotalFee = (PAYMENT_AMOUNT * TOTAL_BPS) / 10000;
        uint256 expectedProtocolFee = (PAYMENT_AMOUNT * PROTOCOL_BPS) / 10000;
        assertEq(token.balanceOf(receiver) - receiverBefore, PAYMENT_AMOUNT - expectedTotalFee, "receiver net amount");
        assertEq(token.balanceOf(address(operator)), expectedTotalFee, "operator holds total fee");
        assertEq(
            operator.accumulatedProtocolFees(address(token)), expectedProtocolFee, "protocol fee tracked internally"
        );
    }

    /// @notice Two-phase contract-path: the escrow's 4-arg `authorize` already shares the operator
    ///         selector, so it dispatched before and after the fix — asserted here for parity.
    function test_ContractPath_AuthorizeDispatchesViaEscrowSelector() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _paymentInfo();

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        bytes memory data =
            abi.encodeCall(AuthCaptureEscrow.authorize, (paymentInfo, PAYMENT_AMOUNT, address(collector), ""));

        vm.prank(facilitator);
        (bool ok,) = address(operator).call(data);
        assertTrue(ok, "forwarded escrow authorize selector must dispatch into the operator");

        (, uint120 capturable,) = escrow.paymentState(escrow.getHash(paymentInfo));
        assertEq(capturable, uint120(PAYMENT_AMOUNT), "authorize held funds in escrow");
    }

    /// @notice The ignored 6-arg fee fields cannot redirect fees: even with a bogus feeReceiver and
    ///         an out-of-band feeBps, the operator recomputes fees and pins the receiver to itself.
    function test_ContractPath_Charge_IgnoresSuppliedFeeArgs() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _paymentInfo();

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        bytes memory data = abi.encodeCall(
            AuthCaptureEscrow.charge,
            (paymentInfo, PAYMENT_AMOUNT, address(collector), "", uint16(9999), makeAddr("attackerFeeReceiver"))
        );

        vm.prank(facilitator);
        (bool ok,) = address(operator).call(data);
        assertTrue(ok, "supplied fee args are ignored, not validated, so the call still dispatches");

        uint256 expectedTotalFee = (PAYMENT_AMOUNT * TOTAL_BPS) / 10000;
        assertEq(token.balanceOf(makeAddr("attackerFeeReceiver")), 0, "no fees leak to the supplied feeReceiver");
        assertEq(token.balanceOf(address(operator)), expectedTotalFee, "operator still holds the recomputed fee");
    }

    // ============ Helpers ============

    function _paymentInfo() internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: uint16(TOTAL_BPS),
            maxFeeBps: uint16(TOTAL_BPS),
            feeReceiver: address(operator),
            salt: 12345
        });
    }

    function _operatorConfig(address feeCalculator)
        internal
        view
        returns (PaymentOperatorFactory.OperatorConfig memory)
    {
        return PaymentOperatorFactory.OperatorConfig({
            feeReceiver: operatorFeeRecipient,
            feeCalculator: feeCalculator,
            authorizePreActionCondition: address(0),
            authorizePostActionHook: address(0),
            chargePreActionCondition: address(0),
            chargePostActionHook: address(0),
            capturePreActionCondition: address(0),
            capturePostActionHook: address(0),
            voidPreActionCondition: address(0),
            voidPostActionHook: address(0),
            refundPreActionCondition: address(0),
            refundPostActionHook: address(0)
        });
    }
}
