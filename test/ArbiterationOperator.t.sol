// SPDX-License-Identifier: MIT
pragma solidity >=0.8.33 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {ArbiterationOperator} from "../src/commerce-payments/operator/ArbiterationOperator.sol";
import {ArbiterationOperatorAccess} from "../src/commerce-payments/operator/ArbiterationOperatorAccess.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockEscrow} from "./mocks/MockEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ArbiterationOperatorTest is Test {
    ArbiterationOperator public operator;
    MockERC20 public token;
    MockEscrow public escrow;
    
    address public owner;
    address public protocolFeeRecipient;
    address public merchant;
    address public arbiter;
    address public payer;
    
    uint256 public constant MAX_TOTAL_FEE_RATE = 50; // 0.5 bps
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 25; // 25%
    uint256 public constant REFUND_DELAY = 7 days;
    uint256 public constant INITIAL_BALANCE = 1000000 * 10**18;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10**18;
    
    event AuthorizationCreated(
        bytes32 indexed authorizationId,
        address indexed payer,
        address indexed merchant,
        uint256 amount,
        uint256 timestamp
    );
    
    event CaptureExecuted(
        bytes32 indexed authorizationId,
        uint256 amount,
        uint256 timestamp
    );
    
    event RefundExecuted(
        bytes32 indexed authorizationId,
        address indexed recipient,
        uint256 amount,
        bool wasCaptured
    );
    
    event MerchantRegistered(
        address indexed merchant,
        address indexed arbiter,
        uint256 refundDelay
    );
    
    function setUp() public {
        owner = address(this);
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        merchant = makeAddr("merchant");
        arbiter = makeAddr("arbiter");
        payer = makeAddr("payer");
        
        // Deploy mock contracts
        token = new MockERC20("Test Token", "TEST");
        escrow = new MockEscrow();
        
        // Deploy operator
        operator = new ArbiterationOperator(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE
        );
        
        // Setup balances
        token.mint(payer, INITIAL_BALANCE);
        token.mint(merchant, INITIAL_BALANCE);
        
        // Register merchant
        operator.registerMerchant(merchant, arbiter, REFUND_DELAY);
        
        // Approve escrow to spend tokens
        vm.prank(payer);
        token.approve(address(escrow), type(uint256).max);
        
        // Approve escrow for merchant (needed for post-capture refunds)
        vm.prank(merchant);
        token.approve(address(escrow), type(uint256).max);
    }
    
    // ============ Constructor Tests ============
    
    function test_Constructor_SetsCorrectValues() public {
        assertEq(address(operator.ESCROW()), address(escrow));
        assertEq(operator.protocolFeeRecipient(), protocolFeeRecipient);
        assertEq(operator.MAX_TOTAL_FEE_RATE(), MAX_TOTAL_FEE_RATE);
        assertEq(operator.PROTOCOL_FEE_PERCENTAGE(), PROTOCOL_FEE_PERCENTAGE);
        assertEq(operator.MAX_ARBITER_FEE_RATE(), (MAX_TOTAL_FEE_RATE * 75) / 100); // 75% of total
        assertEq(operator.feesEnabled(), false);
        assertEq(operator.owner(), owner);
    }
    
    function test_Constructor_RevertsOnZeroEscrow() public {
        vm.expectRevert(ArbiterationOperator.ZeroAddress.selector);
        new ArbiterationOperator(
            address(0),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE
        );
    }
    
    function test_Constructor_RevertsOnZeroProtocolFeeRecipient() public {
        vm.expectRevert(ArbiterationOperator.ZeroAddress.selector);
        new ArbiterationOperator(
            address(escrow),
            address(0),
            MAX_TOTAL_FEE_RATE,
            PROTOCOL_FEE_PERCENTAGE
        );
    }
    
    function test_Constructor_RevertsOnZeroMaxTotalFeeRate() public {
        vm.expectRevert(ArbiterationOperator.ZeroAmount.selector);
        new ArbiterationOperator(
            address(escrow),
            protocolFeeRecipient,
            0,
            PROTOCOL_FEE_PERCENTAGE
        );
    }
    
    function test_Constructor_RevertsOnInvalidProtocolFeePercentage() public {
        vm.expectRevert(ArbiterationOperator.TotalFeeRateExceedsMax.selector);
        new ArbiterationOperator(
            address(escrow),
            protocolFeeRecipient,
            MAX_TOTAL_FEE_RATE,
            101 // > 100%
        );
    }
    
    // ============ Merchant Registration Tests ============
    
    function test_RegisterMerchant_Success() public {
        address newMerchant = makeAddr("newMerchant");
        address newArbiter = makeAddr("newArbiter");
        uint256 newRefundDelay = 14 days;
        
        vm.expectEmit(true, true, false, true);
        emit MerchantRegistered(newMerchant, newArbiter, newRefundDelay);
        
        operator.registerMerchant(newMerchant, newArbiter, newRefundDelay);
        
        (address storedArbiter, uint256 storedDelay) = operator.merchantConfigs(newMerchant);
        assertEq(storedArbiter, newArbiter);
        assertEq(storedDelay, newRefundDelay);
        assertTrue(operator.isMerchantRegistered(newMerchant));
        assertEq(operator.getArbiter(newMerchant), newArbiter);
    }
    
    function test_RegisterMerchant_RevertsOnZeroMerchant() public {
        vm.expectRevert(ArbiterationOperator.ZeroAddress.selector);
        operator.registerMerchant(address(0), arbiter, REFUND_DELAY);
    }
    
    function test_RegisterMerchant_RevertsOnZeroArbiter() public {
        vm.expectRevert(ArbiterationOperator.ZeroAddress.selector);
        operator.registerMerchant(merchant, address(0), REFUND_DELAY);
    }
    
    function test_RegisterMerchant_RevertsOnZeroRefundDelay() public {
        vm.expectRevert(ArbiterationOperator.InvalidRefundDelay.selector);
        operator.registerMerchant(merchant, arbiter, 0);
    }
    
    function test_RegisterMerchant_RevertsOnAlreadyRegistered() public {
        vm.expectRevert(ArbiterationOperator.AlreadyRegistered.selector);
        operator.registerMerchant(merchant, arbiter, REFUND_DELAY);
    }
    
    function test_UpdateMerchantArbiter_Success() public {
        address newArbiter = makeAddr("newArbiter");
        
        vm.prank(merchant);
        vm.expectEmit(true, true, false, true);
        emit ArbiterationOperator.MerchantArbiterUpdated(merchant, arbiter, newArbiter);
        
        operator.updateMerchantArbiter(newArbiter);
        
        (address storedArbiter,) = operator.merchantConfigs(merchant);
        assertEq(storedArbiter, newArbiter);
        assertEq(operator.getArbiter(merchant), newArbiter);
    }
    
    function test_UpdateMerchantArbiter_RevertsOnNotMerchant() public {
        vm.expectRevert(ArbiterationOperatorAccess.MerchantNotRegistered.selector);
        operator.updateMerchantArbiter(makeAddr("newArbiter"));
    }
    
    function test_UpdateMerchantArbiter_RevertsOnZeroArbiter() public {
        vm.prank(merchant);
        vm.expectRevert(ArbiterationOperator.ZeroAddress.selector);
        operator.updateMerchantArbiter(address(0));
    }
    
    function test_UpdateMerchantRefundDelay_Success() public {
        uint256 newDelay = 14 days;
        
        vm.prank(merchant);
        vm.expectEmit(true, true, false, true);
        emit ArbiterationOperator.MerchantRefundDelayUpdated(merchant, REFUND_DELAY, newDelay);
        
        operator.updateMerchantRefundDelay(newDelay);
        
        (, uint256 storedDelay) = operator.merchantConfigs(merchant);
        assertEq(storedDelay, newDelay);
    }
    
    function test_UpdateMerchantRefundDelay_RevertsOnNotMerchant() public {
        vm.expectRevert(ArbiterationOperatorAccess.MerchantNotRegistered.selector);
        operator.updateMerchantRefundDelay(14 days);
    }
    
    function test_UpdateMerchantRefundDelay_RevertsOnZeroDelay() public {
        vm.prank(merchant);
        vm.expectRevert(ArbiterationOperator.InvalidRefundDelay.selector);
        operator.updateMerchantRefundDelay(0);
    }
    
    // ============ Authorization Tests ============
    
    function test_Authorize_Success() public {
        vm.prank(payer);
        bytes32 authId = operator.authorize(
            payer,
            merchant,
            address(token),
            PAYMENT_AMOUNT,
            block.timestamp + 1 days,
            ""
        );
        
        ArbiterationOperator.AuthorizationData memory auth = operator.getAuthorization(authId);
        assertEq(auth.payer, payer);
        assertEq(auth.merchant, merchant);
        assertEq(auth.arbiter, arbiter);
        assertEq(auth.token, address(token));
        assertEq(auth.amount, PAYMENT_AMOUNT);
        assertEq(auth.captured, false);
        assertEq(auth.capturedAmount, 0);
        assertEq(auth.refundedAmount, 0);
        assertEq(auth.refundDelay, REFUND_DELAY);
    }
    
    function test_Authorize_RevertsOnZeroPayer() public {
        vm.expectRevert(ArbiterationOperator.ZeroAddress.selector);
        operator.authorize(
            address(0),
            merchant,
            address(token),
            PAYMENT_AMOUNT,
            block.timestamp + 1 days,
            ""
        );
    }
    
    function test_Authorize_RevertsOnZeroMerchant() public {
        vm.expectRevert(ArbiterationOperator.ZeroAddress.selector);
        operator.authorize(
            payer,
            address(0),
            address(token),
            PAYMENT_AMOUNT,
            block.timestamp + 1 days,
            ""
        );
    }
    
    function test_Authorize_RevertsOnUnregisteredMerchant() public {
        vm.expectRevert(ArbiterationOperatorAccess.MerchantNotRegistered.selector);
        operator.authorize(
            payer,
            makeAddr("unregistered"),
            address(token),
            PAYMENT_AMOUNT,
            block.timestamp + 1 days,
            ""
        );
    }
    
    function test_Authorize_RevertsOnZeroAmount() public {
        vm.expectRevert(ArbiterationOperator.ZeroAmount.selector);
        operator.authorize(
            payer,
            merchant,
            address(token),
            0,
            block.timestamp + 1 days,
            ""
        );
    }
    
    // ============ Capture Tests ============
    
    function test_Capture_Success() public {
        bytes32 authId = _authorize();
        
        // Fast forward past refund delay
        vm.warp(block.timestamp + REFUND_DELAY + 1);
        
        uint256 merchantBalanceBefore = token.balanceOf(merchant);
        uint256 protocolBalanceBefore = token.balanceOf(protocolFeeRecipient);
        uint256 arbiterBalanceBefore = token.balanceOf(arbiter);
        
        vm.prank(merchant);
        vm.expectEmit(true, false, false, true);
        emit CaptureExecuted(authId, PAYMENT_AMOUNT, block.timestamp);
        
        operator.capture(authId, PAYMENT_AMOUNT);
        
        ArbiterationOperator.AuthorizationData memory auth = operator.getAuthorization(authId);
        assertTrue(auth.captured);
        assertEq(auth.capturedAmount, PAYMENT_AMOUNT);
        
        // Check balances (fees disabled by default, so arbiter gets all fees)
        uint256 totalFee = (PAYMENT_AMOUNT * MAX_TOTAL_FEE_RATE) / 10000;
        uint256 merchantAmount = PAYMENT_AMOUNT - totalFee;
        
        assertEq(token.balanceOf(merchant), merchantBalanceBefore + merchantAmount);
        assertEq(token.balanceOf(protocolFeeRecipient), protocolBalanceBefore); // Fees disabled
        assertEq(token.balanceOf(arbiter), arbiterBalanceBefore + totalFee);
    }
    
    function test_Capture_WithProtocolFeesEnabled() public {
        // Enable protocol fees
        operator.setFeesEnabled(true);
        
        bytes32 authId = _authorize();
        vm.warp(block.timestamp + REFUND_DELAY + 1);
        
        uint256 protocolBalanceBefore = token.balanceOf(protocolFeeRecipient);
        uint256 arbiterBalanceBefore = token.balanceOf(arbiter);
        
        vm.prank(merchant);
        operator.capture(authId, PAYMENT_AMOUNT);
        
        uint256 totalFee = (PAYMENT_AMOUNT * MAX_TOTAL_FEE_RATE) / 10000;
        uint256 protocolFee = (totalFee * PROTOCOL_FEE_PERCENTAGE) / 100;
        uint256 arbiterFee = totalFee - protocolFee;
        
        assertEq(token.balanceOf(protocolFeeRecipient), protocolBalanceBefore + protocolFee);
        assertEq(token.balanceOf(arbiter), arbiterBalanceBefore + arbiterFee);
    }
    
    function test_Capture_RevertsOnNotMerchant() public {
        bytes32 authId = _authorize();
        vm.warp(block.timestamp + REFUND_DELAY + 1);
        
        vm.expectRevert(ArbiterationOperatorAccess.NotMerchant.selector);
        operator.capture(authId, PAYMENT_AMOUNT);
    }
    
    function test_Capture_RevertsOnAlreadyCaptured() public {
        bytes32 authId = _authorize();
        vm.warp(block.timestamp + REFUND_DELAY + 1);
        
        vm.prank(merchant);
        operator.capture(authId, PAYMENT_AMOUNT);
        
        vm.prank(merchant);
        vm.expectRevert(ArbiterationOperator.AlreadyCaptured.selector);
        operator.capture(authId, PAYMENT_AMOUNT);
    }
    
    function test_Capture_RevertsOnEscrowTimeNotPassed() public {
        bytes32 authId = _authorize();
        
        vm.prank(merchant);
        vm.expectRevert(ArbiterationOperator.EscrowTimeNotPassed.selector);
        operator.capture(authId, PAYMENT_AMOUNT);
    }
    
    function test_Capture_RevertsOnZeroAmount() public {
        bytes32 authId = _authorize();
        vm.warp(block.timestamp + REFUND_DELAY + 1);
        
        vm.prank(merchant);
        vm.expectRevert(ArbiterationOperator.ZeroAmount.selector);
        operator.capture(authId, 0);
    }
    
    function test_Capture_RevertsOnAmountExceedsAvailable() public {
        bytes32 authId = _authorize();
        vm.warp(block.timestamp + REFUND_DELAY + 1);
        
        vm.prank(merchant);
        vm.expectRevert(ArbiterationOperator.AmountExceedsAvailable.selector);
        operator.capture(authId, PAYMENT_AMOUNT + 1);
    }
    
    // ============ Refund Tests ============
    
    function test_RefundInEscrow_Success() public {
        bytes32 authId = _authorize();
        
        uint256 payerBalanceBefore = token.balanceOf(payer);
        uint256 refundAmount = PAYMENT_AMOUNT / 2;
        
        vm.prank(merchant);
        vm.expectEmit(true, true, false, true);
        emit RefundExecuted(authId, payer, refundAmount, false);
        
        operator.refundInEscrow(authId, refundAmount);
        
        ArbiterationOperator.AuthorizationData memory auth = operator.getAuthorization(authId);
        assertEq(auth.refundedAmount, refundAmount);
        assertFalse(auth.captured);
        assertEq(token.balanceOf(payer), payerBalanceBefore + refundAmount);
    }
    
    function test_RefundInEscrow_ByArbiter() public {
        bytes32 authId = _authorize();
        
        uint256 payerBalanceBefore = token.balanceOf(payer);
        uint256 refundAmount = PAYMENT_AMOUNT / 2;
        
        vm.prank(arbiter);
        operator.refundInEscrow(authId, refundAmount);
        
        assertEq(token.balanceOf(payer), payerBalanceBefore + refundAmount);
    }
    
    function test_RefundInEscrow_PartialRefund() public {
        bytes32 authId = _authorize();
        
        uint256 firstRefund = PAYMENT_AMOUNT / 3;
        uint256 secondRefund = PAYMENT_AMOUNT / 3;
        
        vm.prank(merchant);
        operator.refundInEscrow(authId, firstRefund);
        
        vm.prank(merchant);
        operator.refundInEscrow(authId, secondRefund);
        
        ArbiterationOperator.AuthorizationData memory auth = operator.getAuthorization(authId);
        assertEq(auth.refundedAmount, firstRefund + secondRefund);
    }
    
    function test_RefundInEscrow_RevertsOnNotMerchantOrArbiter() public {
        bytes32 authId = _authorize();
        
        vm.expectRevert(ArbiterationOperatorAccess.NotMerchantOrArbiter.selector);
        operator.refundInEscrow(authId, PAYMENT_AMOUNT / 2);
    }
    
    function test_RefundInEscrow_RevertsOnAlreadyCaptured() public {
        bytes32 authId = _authorize();
        vm.warp(block.timestamp + REFUND_DELAY + 1);
        
        vm.prank(merchant);
        operator.capture(authId, PAYMENT_AMOUNT);
        
        vm.prank(merchant);
        vm.expectRevert(ArbiterationOperator.AlreadyCaptured.selector);
        operator.refundInEscrow(authId, PAYMENT_AMOUNT / 2);
    }
    
    function test_RefundPostEscrow_Success() public {
        bytes32 authId = _authorize();
        vm.warp(block.timestamp + REFUND_DELAY + 1);
        
        vm.prank(merchant);
        operator.capture(authId, PAYMENT_AMOUNT);
        
        uint256 payerBalanceBefore = token.balanceOf(payer);
        uint256 refundAmount = PAYMENT_AMOUNT / 2;
        
        vm.prank(merchant);
        operator.refundPostEscrow(authId, refundAmount);
        
        ArbiterationOperator.AuthorizationData memory auth = operator.getAuthorization(authId);
        assertEq(auth.refundedAmount, refundAmount);
        assertEq(token.balanceOf(payer), payerBalanceBefore + refundAmount);
    }
    
    function test_RefundPostEscrow_RevertsOnNotCaptured() public {
        bytes32 authId = _authorize();
        
        vm.prank(merchant);
        vm.expectRevert(ArbiterationOperator.NotCaptured.selector);
        operator.refundPostEscrow(authId, PAYMENT_AMOUNT / 2);
    }
    
    function test_RefundPostEscrow_RevertsOnNotMerchant() public {
        bytes32 authId = _authorize();
        vm.warp(block.timestamp + REFUND_DELAY + 1);
        
        vm.prank(merchant);
        operator.capture(authId, PAYMENT_AMOUNT);
        
        vm.expectRevert(ArbiterationOperatorAccess.NotMerchant.selector);
        operator.refundPostEscrow(authId, PAYMENT_AMOUNT / 2);
    }
    
    // ============ Void Tests ============
    
    function test_Void_Success() public {
        bytes32 authId = _authorize();
        
        uint256 payerBalanceBefore = token.balanceOf(payer);
        
        vm.prank(merchant);
        operator.void(authId);
        
        // Payer should receive full refund
        assertEq(token.balanceOf(payer), payerBalanceBefore + PAYMENT_AMOUNT);
    }
    
    function test_Void_ByArbiter() public {
        bytes32 authId = _authorize();
        
        vm.prank(arbiter);
        operator.void(authId);
        
        // Should succeed
        assertTrue(true);
    }
    
    function test_Void_RevertsOnAlreadyCaptured() public {
        bytes32 authId = _authorize();
        vm.warp(block.timestamp + REFUND_DELAY + 1);
        
        vm.prank(merchant);
        operator.capture(authId, PAYMENT_AMOUNT);
        
        vm.prank(merchant);
        vm.expectRevert(ArbiterationOperator.AlreadyCaptured.selector);
        operator.void(authId);
    }
    
    function test_Void_RevertsOnAlreadyRefunded() public {
        bytes32 authId = _authorize();
        
        vm.prank(merchant);
        operator.refundInEscrow(authId, PAYMENT_AMOUNT / 2);
        
        vm.prank(merchant);
        vm.expectRevert(ArbiterationOperator.AlreadyRefunded.selector);
        operator.void(authId);
    }
    
    // ============ Fee Management Tests ============
    
    function test_SetFeesEnabled_OnlyOwner() public {
        vm.expectEmit(true, false, false, true);
        emit ArbiterationOperator.ProtocolFeesEnabledUpdated(true);
        
        operator.setFeesEnabled(true);
        assertTrue(operator.feesEnabled());
        
        operator.setFeesEnabled(false);
        assertFalse(operator.feesEnabled());
    }
    
    function test_SetFeesEnabled_RevertsOnNotOwner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        operator.setFeesEnabled(true);
    }
    
    // ============ View Functions Tests ============
    
    function test_IsCaptured() public {
        bytes32 authId = _authorize();
        assertFalse(operator.isCaptured(authId));
        
        vm.warp(block.timestamp + REFUND_DELAY + 1);
        vm.prank(merchant);
        operator.capture(authId, PAYMENT_AMOUNT);
        
        assertTrue(operator.isCaptured(authId));
    }
    
    function test_GetPayer() public {
        bytes32 authId = _authorize();
        assertEq(operator.getPayer(authId), payer);
    }
    
    function test_GetPayer_RevertsOnNonExistent() public {
        vm.expectRevert(ArbiterationOperator.ZeroAddress.selector);
        operator.getPayer(bytes32(uint256(123)));
    }
    
    // ============ Helper Functions ============
    
    function _authorize() internal returns (bytes32) {
        vm.prank(payer);
        return operator.authorize(
            payer,
            merchant,
            address(token),
            PAYMENT_AMOUNT,
            block.timestamp + 1 days,
            ""
        );
    }
}

