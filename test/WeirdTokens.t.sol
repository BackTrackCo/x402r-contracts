// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../src/operator/arbitration/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../src/operator/PaymentOperatorFactory.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {PreApprovalPaymentCollector} from "commerce-payments/collectors/PreApprovalPaymentCollector.sol";
import {ProtocolFeeConfig} from "../src/fees/ProtocolFeeConfig.sol";
import {MockFeeOnTransferToken} from "./mocks/MockFeeOnTransferToken.sol";
import {MockRebasingToken} from "./mocks/MockRebasingToken.sol";

/**
 * @title WeirdTokensTest
 * @notice Test suite for weird/non-standard ERC20 token behaviors
 * @dev Based on Trail of Bits Weird ERC20 Database
 */
contract WeirdTokensTest is Test {
    PaymentOperator public operator;
    PaymentOperatorFactory public factory;
    AuthCaptureEscrow public escrow;
    PreApprovalPaymentCollector public collector;
    ProtocolFeeConfig public protocolFeeConfig;

    MockFeeOnTransferToken public feeToken;
    MockRebasingToken public rebaseToken;

    address public owner;
    address public protocolFeeRecipient;
    address public payer;
    address public receiver;

    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        payer = makeAddr("payer");
        receiver = makeAddr("receiver");

        // Deploy infrastructure
        escrow = new AuthCaptureEscrow();
        collector = new PreApprovalPaymentCollector(address(escrow));
        protocolFeeConfig = new ProtocolFeeConfig(address(0), protocolFeeRecipient, owner);
        factory = new PaymentOperatorFactory(
            address(escrow), address(protocolFeeConfig), owner
        );

        // Deploy operator
        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: protocolFeeRecipient,
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
        operator = PaymentOperator(factory.deployOperator(config));

        // Deploy weird tokens
        feeToken = new MockFeeOnTransferToken();
        rebaseToken = new MockRebasingToken();
    }

    function _createPaymentInfo(address token) internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: address(operator),
            payer: payer,
            receiver: receiver,
            token: token,
            maxAmount: uint120(PAYMENT_AMOUNT),
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: 0,
            maxFeeBps: 0,
            feeReceiver: address(operator),
            salt: 12345
        });
    }

    // ============ Fee-on-Transfer Token Tests ============

    function test_FeeOnTransferToken_AuthorizeRejected() public {
        // Setup
        feeToken.mint(payer, PAYMENT_AMOUNT * 2);
        vm.prank(payer);
        feeToken.approve(address(collector), type(uint256).max);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(feeToken));

        // Pre-approve
        vm.prank(payer);
        collector.preApprove(paymentInfo);

        // Attempt authorization - should revert because balance check fails
        // Fee token takes 1% fee, so only 99% arrives but we expect 100%
        vm.expectRevert(AuthCaptureEscrow.TokenCollectionFailed.selector);
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");
    }

    function test_FeeOnTransferToken_ChargeRejected() public {
        // Setup
        feeToken.mint(payer, PAYMENT_AMOUNT * 2);
        vm.prank(payer);
        feeToken.approve(address(collector), type(uint256).max);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(feeToken));

        // Pre-approve
        vm.prank(payer);
        collector.preApprove(paymentInfo);

        // Attempt charge - should revert for same reason
        vm.expectRevert(AuthCaptureEscrow.TokenCollectionFailed.selector);
        operator.charge(paymentInfo, PAYMENT_AMOUNT, address(collector), "");
    }

    function test_FeeOnTransferToken_VerifyFeeAmount() public view {
        // Verify the fee token actually takes fees
        uint256 amount = 1000e18;
        uint256 expectedFee = (amount * feeToken.TRANSFER_FEE_BPS()) / 10000;
        uint256 expectedReceived = amount - expectedFee;

        assertEq(expectedFee, 10e18); // 1% of 1000 = 10
        assertEq(expectedReceived, 990e18); // 990 received
    }

    // ============ Rebasing Token Tests ============

    function test_RebasingToken_InitialAuthorizeWorks() public {
        // Mint tokens and approve
        rebaseToken.mint(payer, PAYMENT_AMOUNT * 2);
        vm.prank(payer);
        rebaseToken.approve(address(collector), type(uint256).max);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(rebaseToken));

        // Pre-approve
        vm.prank(payer);
        collector.preApprove(paymentInfo);

        // Initial authorization should work (no rebase yet)
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // Verify authorization
        bytes32 hash = escrow.getHash(paymentInfo);
        (bool hasCollected, uint256 capturableAmount, uint256 refundableAmount) = escrow.paymentState(hash);

        assertTrue(hasCollected);
        assertEq(capturableAmount, PAYMENT_AMOUNT);
        assertEq(refundableAmount, 0);
    }

    function test_RebasingToken_PositiveRebaseBreaksAccounting() public {
        // Authorize payment
        rebaseToken.mint(payer, PAYMENT_AMOUNT * 2);
        vm.prank(payer);
        rebaseToken.approve(address(collector), type(uint256).max);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(rebaseToken));

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // Get token store address
        address tokenStore = escrow.getTokenStore(address(operator));

        // Record balance before rebase
        uint256 balanceBefore = rebaseToken.balanceOf(tokenStore);
        assertEq(balanceBefore, PAYMENT_AMOUNT);

        // Simulate positive rebase (10% increase)
        rebaseToken.rebase(1.1e18); // 1.1x multiplier

        // Balance increases but protocol doesn't know!
        uint256 balanceAfter = rebaseToken.balanceOf(tokenStore);
        assertEq(balanceAfter, PAYMENT_AMOUNT * 11 / 10); // 10% more

        // Protocol still thinks it has PAYMENT_AMOUNT
        bytes32 hash = escrow.getHash(paymentInfo);
        (bool hasCollected, uint256 capturableAmount,) = escrow.paymentState(hash);

        assertTrue(hasCollected);
        assertEq(capturableAmount, PAYMENT_AMOUNT); // Still the old amount!

        // This is the accounting error - protocol thinks 1000, actually has 1100
        assertLt(capturableAmount, balanceAfter);
    }

    function test_RebasingToken_NegativeRebaseBreaksAccounting() public {
        // Authorize payment
        rebaseToken.mint(payer, PAYMENT_AMOUNT * 2);
        vm.prank(payer);
        rebaseToken.approve(address(collector), type(uint256).max);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(rebaseToken));

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // Get token store address
        address tokenStore = escrow.getTokenStore(address(operator));

        // Record balance before rebase
        uint256 balanceBefore = rebaseToken.balanceOf(tokenStore);
        assertEq(balanceBefore, PAYMENT_AMOUNT);

        // Simulate negative rebase (10% decrease)
        rebaseToken.rebase(0.9e18); // 0.9x multiplier

        // Balance decreases but protocol doesn't know!
        uint256 balanceAfter = rebaseToken.balanceOf(tokenStore);
        assertEq(balanceAfter, PAYMENT_AMOUNT * 9 / 10); // 10% less

        // Protocol still thinks it has PAYMENT_AMOUNT
        bytes32 hash = escrow.getHash(paymentInfo);
        (bool hasCollected, uint256 capturableAmount,) = escrow.paymentState(hash);

        assertTrue(hasCollected);
        assertEq(capturableAmount, PAYMENT_AMOUNT); // Still the old amount!

        // This is the accounting error - protocol thinks 1000, actually has 900
        assertGt(capturableAmount, balanceAfter);

        // Attempting to release full amount would fail (insufficient balance)
        vm.prank(receiver);
        vm.expectRevert();
        operator.release(paymentInfo, PAYMENT_AMOUNT);
    }

    function test_RebasingToken_DocumentedRisk() public {
        // This test documents why rebasing tokens are not supported

        // Setup
        rebaseToken.mint(payer, PAYMENT_AMOUNT * 2);
        vm.prank(payer);
        rebaseToken.approve(address(collector), type(uint256).max);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(rebaseToken));

        vm.prank(payer);
        collector.preApprove(paymentInfo);

        // 1. Authorize 1000 tokens
        operator.authorize(paymentInfo, PAYMENT_AMOUNT, address(collector), "");

        // 2. Positive rebase to 1100 tokens in escrow
        rebaseToken.rebase(1.1e18);

        // 3. Release succeeds (takes 1000 out of 1100)
        vm.prank(receiver);
        operator.release(paymentInfo, PAYMENT_AMOUNT);

        // 4. Now there's 100 tokens stuck in escrow that no one owns!
        address tokenStore = escrow.getTokenStore(address(operator));
        uint256 stuckBalance = rebaseToken.balanceOf(tokenStore);

        // These tokens are stuck - protocol doesn't track them
        assertGt(stuckBalance, 0);

        // Negative rebase is worse - release would fail due to insufficient balance
    }
}
