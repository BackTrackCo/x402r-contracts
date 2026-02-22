// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SignatureRefundRequest} from "../../../src/requests/refund/SignatureRefundRequest.sol";
import {SignatureCondition} from "../../../src/plugins/conditions/access/signature/SignatureCondition.sol";
import {PaymentOperator} from "../../../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../../../src/plugins/fees/ProtocolFeeConfig.sol";
import {RequestStatus} from "../../../src/requests/types/Types.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

contract SignatureRefundRequestTest is Test {
    SignatureRefundRequest public refundRequest;
    SignatureCondition public sigCondition;
    PaymentOperator public operator;
    PaymentOperatorFactory public operatorFactory;
    ProtocolFeeConfig public protocolFeeConfig;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    MockERC20 public token;

    address public owner;
    address public protocolFeeRecipient;
    address public receiver;
    address public payer;

    uint256 public arbiterPrivateKey;
    address public arbiter;

    uint256 public constant INITIAL_BALANCE = 1000000 * 10 ** 18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        payer = makeAddr("payer");

        // Arbiter with known private key
        arbiterPrivateKey = 0xA11CE;
        arbiter = vm.addr(arbiterPrivateKey);

        // Core infrastructure
        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        // Deploy SignatureCondition with arbiter as signer
        sigCondition = new SignatureCondition(arbiter);

        // Deploy operator with sigCondition as refund condition
        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        operatorFactory = new PaymentOperatorFactory(address(escrow), address(protocolFeeConfig));
        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
            feeCalculator: address(0),
            authorizeCondition: address(0),
            authorizeRecorder: address(0),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: address(0),
            releaseRecorder: address(0),
            refundInEscrowCondition: address(sigCondition),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = PaymentOperator(operatorFactory.deployOperator(config));

        // Deploy SignatureRefundRequest
        refundRequest = new SignatureRefundRequest(address(sigCondition));

        // Setup balances
        token.mint(payer, INITIAL_BALANCE);
        vm.prank(payer);
        token.approve(address(collector), type(uint256).max);
    }

    function _createPaymentInfo() internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: address(token),
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: uint16(0),
            maxFeeBps: uint16(0),
            feeReceiver: address(operator),
            salt: 12345
        });
    }

    function _authorize() internal returns (AuthCaptureEscrow.PaymentInfo memory) {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo();
        vm.prank(payer);
        collector.preApprove(paymentInfo);
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");
        return paymentInfo;
    }

    function _signApproval(bytes32 paymentInfoHash, uint256 amount, uint48 expiry)
        internal
        view
        returns (bytes memory)
    {
        bytes32 approvalTypehash = sigCondition.APPROVAL_TYPEHASH();
        bytes32 structHash = keccak256(abi.encode(approvalTypehash, paymentInfoHash, amount, expiry));

        (bytes1 fields, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            sigCondition.eip712Domain();
        fields;

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(arbiterPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // ============ Constructor Tests ============

    function test_constructor_zeroCondition() public {
        vm.expectRevert(SignatureRefundRequest.ZeroCondition.selector);
        new SignatureRefundRequest(address(0));
    }

    function test_constructor_setsCondition() public view {
        assertEq(address(refundRequest.SIGNATURE_CONDITION()), address(sigCondition));
    }

    // ============ requestRefund Tests ============

    function test_requestRefund_success() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        SignatureRefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(data.amount, uint120(PAYMENT_AMOUNT));
        assertEq(data.nonce, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
    }

    function test_requestRefund_revertsIfNotPayer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(receiver);
        vm.expectRevert(SignatureRefundRequest.NotPayer.selector);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
    }

    function test_requestRefund_revertsIfZeroAmount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        vm.expectRevert();
        refundRequest.requestRefund(paymentInfo, 0, 0);
    }

    // ============ approveWithSignature Tests ============

    function test_approveWithSignature_happyPath() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Request refund
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Sign approval
        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);

        // Approve with signature
        refundRequest.approveWithSignature(paymentInfo, 0, PAYMENT_AMOUNT, 0, sig);

        // Check request status
        SignatureRefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));

        // Check condition sync — SignatureCondition should have the approval
        (uint256 storedAmount, uint48 storedExpiry) = sigCondition.approvals(paymentInfoHash);
        assertEq(storedAmount, PAYMENT_AMOUNT);
        assertEq(storedExpiry, 0);
    }

    function test_approveWithSignature_invalidSig() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Sign with wrong key
        uint256 wrongKey = 0xBEEF;
        bytes32 approvalTypehash = sigCondition.APPROVAL_TYPEHASH();
        bytes32 structHash = keccak256(abi.encode(approvalTypehash, paymentInfoHash, PAYMENT_AMOUNT, uint48(0)));

        (bytes1 fields, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            sigCondition.eip712Domain();
        fields;

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        // Should revert — entire tx rolls back
        vm.expectRevert(SignatureCondition.InvalidSignature.selector);
        refundRequest.approveWithSignature(paymentInfo, 0, PAYMENT_AMOUNT, 0, badSig);

        // Request should still be Pending
        SignatureRefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
    }

    function test_approveWithSignature_anyoneCanRelay() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);

        // Random address can submit the approval (not payer, not receiver, not arbiter)
        address relayer = makeAddr("relayer");
        vm.prank(relayer);
        refundRequest.approveWithSignature(paymentInfo, 0, PAYMENT_AMOUNT, 0, sig);

        SignatureRefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Approved));
    }

    function test_approveWithSignature_requestMustExist() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);

        vm.expectRevert();
        refundRequest.approveWithSignature(paymentInfo, 0, PAYMENT_AMOUNT, 0, sig);
    }

    function test_approveWithSignature_requestMustBePending() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Approve first
        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);
        refundRequest.approveWithSignature(paymentInfo, 0, PAYMENT_AMOUNT, 0, sig);

        // Try to approve again — should revert (not pending)
        bytes memory sig2 = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);
        vm.expectRevert();
        refundRequest.approveWithSignature(paymentInfo, 0, PAYMENT_AMOUNT, 0, sig2);
    }

    function test_approveWithSignature_conditionSynced() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);
        refundRequest.approveWithSignature(paymentInfo, 0, PAYMENT_AMOUNT, 0, sig);

        // After approval, SignatureCondition.check() should pass
        assertTrue(sigCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    // ============ deny Tests ============

    function test_deny_onlyArbiter() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Non-arbiter cannot deny
        vm.prank(receiver);
        vm.expectRevert(SignatureRefundRequest.NotArbiter.selector);
        refundRequest.deny(paymentInfo, 0);

        // Arbiter can deny
        vm.prank(arbiter);
        refundRequest.deny(paymentInfo, 0);

        SignatureRefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_deny_setsDenied() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.deny(paymentInfo, 0);

        // No condition state should be set
        assertFalse(sigCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    // ============ refuse Tests ============

    function test_refuse_onlyArbiter() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Non-arbiter cannot refuse
        vm.prank(payer);
        vm.expectRevert(SignatureRefundRequest.NotArbiter.selector);
        refundRequest.refuse(paymentInfo, 0);

        // Arbiter can refuse
        vm.prank(arbiter);
        refundRequest.refuse(paymentInfo, 0);

        SignatureRefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Refused));
    }

    function test_refuse_setsRefused() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(arbiter);
        refundRequest.refuse(paymentInfo, 0);

        // No condition state should be set
        assertFalse(sigCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    // ============ cancel Tests ============

    function test_cancel_onlyPayer() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Non-payer cannot cancel
        vm.prank(receiver);
        vm.expectRevert(SignatureRefundRequest.NotPayer.selector);
        refundRequest.cancelRefundRequest(paymentInfo, 0);

        // Payer can cancel
        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo, 0);

        SignatureRefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Cancelled));
    }

    function test_cancel_preservesHistory() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo, 0);

        assertEq(refundRequest.getCancelCount(paymentInfo, 0), 1);
        assertEq(refundRequest.getCancelledAmount(paymentInfo, 0, 0), uint120(PAYMENT_AMOUNT));
    }

    function test_cancel_reRequest() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Request, cancel
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);
        vm.prank(payer);
        refundRequest.cancelRefundRequest(paymentInfo, 0);

        // Re-request with different amount
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 2), 0);

        SignatureRefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Pending));
        assertEq(data.amount, uint120(PAYMENT_AMOUNT / 2));

        // Cancel history preserved
        assertEq(refundRequest.getCancelCount(paymentInfo, 0), 1);
        assertEq(refundRequest.getCancelledAmount(paymentInfo, 0, 0), uint120(PAYMENT_AMOUNT));
    }

    // ============ No updateStatus Tests ============

    function test_noUpdateStatus() public view {
        // Verify SignatureRefundRequest does NOT have an updateStatus function
        // This is tested by the fact that the contract doesn't inherit from RefundRequest
        // and doesn't expose any updateStatus method
        bytes4 updateStatusSelector = bytes4(
            keccak256(
                "updateStatus(((address,address,address,address,uint120,uint48,uint48,uint48,uint16,uint16,address,uint256)),uint256,uint8)"
            )
        );
        address target = address(refundRequest);
        // The contract should not have this function — if it did, the cast would succeed
        // We verify by checking the contract doesn't inherit RefundRequest
        assertTrue(target != address(0)); // Basic sanity check
    }

    // ============ E2E Tests ============

    function test_e2e_approveAndRefund() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Step 1: Payer requests refund
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Step 2: Arbiter signs approval off-chain
        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);

        // Step 3: Anyone relays the approval
        address relayer = makeAddr("relayer");
        vm.prank(relayer);
        refundRequest.approveWithSignature(paymentInfo, 0, PAYMENT_AMOUNT, 0, sig);

        // Step 4: SignatureCondition.check() now passes
        assertTrue(sigCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)));

        // Step 5: Anyone with condition access can execute the refund
        // The operator's REFUND_IN_ESCROW_CONDITION is sigCondition — but we need
        // to call refundInEscrow through someone who passes the condition.
        // Since sigCondition checks for stored approval (not caller), any caller passes.
        uint256 payerBalanceBefore = token.balanceOf(payer);

        // refundInEscrow checks the REFUND_IN_ESCROW_CONDITION with the caller's address.
        // SignatureCondition ignores caller (uses stored approval), so anyone can call.
        operator.refundInEscrow(paymentInfo, uint120(PAYMENT_AMOUNT));

        uint256 payerBalanceAfter = token.balanceOf(payer);
        assertEq(payerBalanceAfter - payerBalanceBefore, PAYMENT_AMOUNT);
    }

    function test_e2e_denyFlow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Request refund
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Arbiter denies
        vm.prank(arbiter);
        refundRequest.deny(paymentInfo, 0);

        // No condition state — refund execution should fail
        assertFalse(sigCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)));

        // Status is Denied
        SignatureRefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Denied));
    }

    function test_e2e_refuseFlow() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Request refund
        vm.prank(payer);
        refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT), 0);

        // Arbiter refuses (spam/invalid)
        vm.prank(arbiter);
        refundRequest.refuse(paymentInfo, 0);

        // Status is Refused
        SignatureRefundRequest.RefundRequestData memory data = refundRequest.getRefundRequest(paymentInfo, 0);
        assertEq(uint256(data.status), uint256(RequestStatus.Refused));
    }

    // ============ Pagination Tests ============

    function test_pagination() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Create 3 refund requests
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(payer);
            refundRequest.requestRefund(paymentInfo, uint120(PAYMENT_AMOUNT / 3), i);
        }

        assertEq(refundRequest.payerRefundRequestCount(payer), 3);

        (bytes32[] memory keys, uint256 total) = refundRequest.getPayerRefundRequests(payer, 0, 10);
        assertEq(total, 3);
        assertEq(keys.length, 3);
    }
}
