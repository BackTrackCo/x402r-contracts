// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SignatureCondition} from "../../../../../src/plugins/conditions/access/signature/SignatureCondition.sol";
import {PaymentOperator} from "../../../../../src/operator/payment/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../../../../src/operator/PaymentOperatorFactory.sol";
import {ProtocolFeeConfig} from "../../../../../src/plugins/fees/ProtocolFeeConfig.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {MockERC20} from "../../../../mocks/MockERC20.sol";
import {AndCondition} from "../../../../../src/plugins/conditions/combinators/AndCondition.sol";
import {OrCondition} from "../../../../../src/plugins/conditions/combinators/OrCondition.sol";
import {ICondition} from "../../../../../src/plugins/conditions/ICondition.sol";

contract SignatureConditionTest is Test {
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

    uint256 public signerPrivateKey;
    address public signer;

    uint256 public constant INITIAL_BALANCE = 1000000 * 10 ** 18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        receiver = makeAddr("receiver");
        payer = makeAddr("payer");

        // Create signer with known private key for EIP-712 signing
        signerPrivateKey = 0xA11CE;
        signer = vm.addr(signerPrivateKey);

        // Deploy core infrastructure
        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");
        collector = new PreApprovalPaymentCollector(address(escrow));

        // Deploy SignatureCondition
        sigCondition = new SignatureCondition(signer);

        // Deploy protocol fee config (no fees)
        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);

        // Deploy operator factory and operator with sigCondition as refund condition
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

        // Setup balances and approvals
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

        // Get EIP-712 domain separator from the condition contract
        (bytes1 fields, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            sigCondition.eip712Domain();

        // Suppress unused variable warnings
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // ============ submitApproval Tests ============

    function test_submitApproval_validSignature() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);

        vm.expectEmit(true, false, false, true);
        emit SignatureCondition.ApprovalSubmitted(paymentInfoHash, PAYMENT_AMOUNT, 0);

        sigCondition.submitApproval(paymentInfoHash, PAYMENT_AMOUNT, 0, sig);

        (uint256 storedAmount, uint48 storedExpiry) = sigCondition.approvals(paymentInfoHash);
        assertEq(storedAmount, PAYMENT_AMOUNT);
        assertEq(storedExpiry, 0);
    }

    function test_submitApproval_invalidSignature() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

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

        vm.expectRevert(SignatureCondition.InvalidSignature.selector);
        sigCondition.submitApproval(paymentInfoHash, PAYMENT_AMOUNT, 0, badSig);
    }

    function test_submitApproval_overwrite() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // First approval
        bytes memory sig1 = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);
        sigCondition.submitApproval(paymentInfoHash, PAYMENT_AMOUNT, 0, sig1);

        // Second approval with different amount overwrites
        uint256 newAmount = PAYMENT_AMOUNT / 2;
        uint48 newExpiry = uint48(block.timestamp + 1 days);
        bytes memory sig2 = _signApproval(paymentInfoHash, newAmount, newExpiry);
        sigCondition.submitApproval(paymentInfoHash, newAmount, newExpiry, sig2);

        (uint256 storedAmount, uint48 storedExpiry) = sigCondition.approvals(paymentInfoHash);
        assertEq(storedAmount, newAmount);
        assertEq(storedExpiry, newExpiry);
    }

    // ============ check() Tests ============

    function test_check_approved() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);
        sigCondition.submitApproval(paymentInfoHash, PAYMENT_AMOUNT, 0, sig);

        assertTrue(sigCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    function test_check_partialAmount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);
        sigCondition.submitApproval(paymentInfoHash, PAYMENT_AMOUNT, 0, sig);

        // Requesting less than approved amount should pass
        assertTrue(sigCondition.check(paymentInfo, PAYMENT_AMOUNT / 2, address(0)));
    }

    function test_check_excessAmount() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT / 2, 0);
        sigCondition.submitApproval(paymentInfoHash, PAYMENT_AMOUNT / 2, 0, sig);

        // Requesting more than approved amount should fail
        assertFalse(sigCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    function test_check_noApproval() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // No approval submitted — should return false
        assertFalse(sigCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    function test_check_expired() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        uint48 expiry = uint48(block.timestamp + 1 hours);
        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, expiry);
        sigCondition.submitApproval(paymentInfoHash, PAYMENT_AMOUNT, expiry, sig);

        // Should pass before expiry
        assertTrue(sigCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)));

        // Warp past expiry
        vm.warp(block.timestamp + 2 hours);
        assertFalse(sigCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    function test_check_noExpiry() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // expiry = 0 means no expiry
        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);
        sigCondition.submitApproval(paymentInfoHash, PAYMENT_AMOUNT, 0, sig);

        // Should pass even far in the future
        vm.warp(block.timestamp + 365 days);
        assertTrue(sigCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    function test_constructor_zeroSigner() public {
        vm.expectRevert(SignatureCondition.ZeroSigner.selector);
        new SignatureCondition(address(0));
    }

    // ============ Composability Tests ============

    function test_composability_andCondition() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Submit approval
        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);
        sigCondition.submitApproval(paymentInfoHash, PAYMENT_AMOUNT, 0, sig);

        // Create And(SignatureCondition, AlwaysTrue-like condition that checks caller == payer)
        // We'll use another SignatureCondition as the second operand (already approved)
        ICondition[] memory conds = new ICondition[](2);
        conds[0] = ICondition(address(sigCondition));
        conds[1] = ICondition(address(sigCondition));
        AndCondition andCond = new AndCondition(conds);

        // Should pass (both conditions are the same approved condition)
        assertTrue(andCond.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    function test_composability_orCondition() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();

        // Create a second SignatureCondition that has NO approval
        SignatureCondition noApprovalCond = new SignatureCondition(makeAddr("other"));

        // Or(sigCondition, noApprovalCond)
        ICondition[] memory conds = new ICondition[](2);
        conds[0] = ICondition(address(sigCondition));
        conds[1] = ICondition(address(noApprovalCond));
        OrCondition orCond = new OrCondition(conds);

        // Neither has approval, should fail
        assertFalse(orCond.check(paymentInfo, PAYMENT_AMOUNT, address(0)));

        // Submit approval on sigCondition
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);
        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);
        sigCondition.submitApproval(paymentInfoHash, PAYMENT_AMOUNT, 0, sig);

        // Now Or should pass (first condition passes)
        assertTrue(orCond.check(paymentInfo, PAYMENT_AMOUNT, address(0)));
    }

    function test_signer_immutable() public view {
        assertEq(sigCondition.SIGNER(), signer);
    }

    // ============ Hash Security Tests ============

    function test_approvalHash_structEncoding() public view {
        bytes32 expectedHash = keccak256("Approval(bytes32 paymentInfoHash,uint256 amount,uint48 expiry)");
        assertEq(sigCondition.APPROVAL_TYPEHASH(), expectedHash);
    }

    function test_domainSeparator_matchesEIP712() public view {
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = sigCondition.eip712Domain();

        fields; // suppress unused
        salt; // suppress unused
        extensions; // suppress unused

        assertEq(name, "SignatureCondition");
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(sigCondition));
    }

    function test_check_expiryBoundary() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        uint48 expiry = uint48(block.timestamp + 1 hours);
        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, expiry);
        sigCondition.submitApproval(paymentInfoHash, PAYMENT_AMOUNT, expiry, sig);

        // At exact expiry, should still pass (uses > not >=)
        vm.warp(expiry);
        assertTrue(sigCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)), "Should pass at exact expiry");

        // One second after expiry, should fail
        vm.warp(expiry + 1);
        assertFalse(sigCondition.check(paymentInfo, PAYMENT_AMOUNT, address(0)), "Should fail 1s after expiry");
    }

    function test_signatureInvalidOnDifferentCondition() public {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _authorize();
        bytes32 paymentInfoHash = escrow.getHash(paymentInfo);

        // Sign approval for sigCondition
        bytes memory sig = _signApproval(paymentInfoHash, PAYMENT_AMOUNT, 0);

        // Deploy a second SignatureCondition with the SAME signer
        SignatureCondition otherCondition = new SignatureCondition(signer);

        // The same signature should NOT work on a different contract
        // because the domain separator includes verifyingContract
        vm.expectRevert(SignatureCondition.InvalidSignature.selector);
        otherCondition.submitApproval(paymentInfoHash, PAYMENT_AMOUNT, 0, sig);
    }
}
