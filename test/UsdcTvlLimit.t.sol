// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {UsdcTvlLimit} from "../src/plugins/conditions/tvl-limit/UsdcTvlLimit.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract UsdcTvlLimitTest is Test {
    UsdcTvlLimit public tvlLimit;
    MockERC20 public usdc;
    MockERC20 public otherToken;
    address public escrow;

    uint256 constant LIMIT = 100_000e6; // $100k with 6 decimals

    address public payer = makeAddr("payer");
    address public receiver = makeAddr("receiver");
    address public operator = makeAddr("operator");

    function setUp() public {
        escrow = makeAddr("escrow");
        usdc = new MockERC20("USD Coin", "USDC");
        otherToken = new MockERC20("Other Token", "OTHER");

        tvlLimit = new UsdcTvlLimit(escrow, address(usdc), LIMIT);
    }

    function _createPaymentInfo(address token) internal view returns (AuthCaptureEscrow.PaymentInfo memory) {
        return AuthCaptureEscrow.PaymentInfo({
            operator: operator,
            payer: payer,
            receiver: receiver,
            token: token,
            maxAmount: 1000e6,
            preApprovalExpiry: uint48(block.timestamp + 1 days),
            authorizationExpiry: uint48(block.timestamp + 7 days),
            refundExpiry: uint48(block.timestamp + 30 days),
            minFeeBps: 0,
            maxFeeBps: 100,
            feeReceiver: operator,
            salt: 12345
        });
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsImmutables() public view {
        assertEq(tvlLimit.ESCROW(), escrow);
        assertEq(tvlLimit.USDC(), address(usdc));
        assertEq(tvlLimit.LIMIT(), LIMIT);
    }

    // ============ Token Whitelist Tests ============

    function test_Check_BlocksNonUsdcToken() public view {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(otherToken));
        assertFalse(tvlLimit.check(paymentInfo, 1000e18, payer));
    }

    function test_Check_BlocksZeroAddressToken() public view {
        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(0));
        assertFalse(tvlLimit.check(paymentInfo, 1000, payer));
    }

    // ============ TVL Limit Tests ============

    function test_Check_AllowsUsdcUnderLimit() public {
        // Escrow has $50k
        usdc.mint(escrow, 50_000e6);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(usdc));

        // $40k payment should be allowed (50k + 40k = 90k < 100k)
        assertTrue(tvlLimit.check(paymentInfo, 40_000e6, payer));
    }

    function test_Check_AllowsUsdcAtExactLimit() public {
        // Escrow has $50k
        usdc.mint(escrow, 50_000e6);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(usdc));

        // $50k payment should be allowed (50k + 50k = 100k = limit)
        assertTrue(tvlLimit.check(paymentInfo, 50_000e6, payer));
    }

    function test_Check_BlocksUsdcOverLimit() public {
        // Escrow has $50k
        usdc.mint(escrow, 50_000e6);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(usdc));

        // $60k payment should be blocked (50k + 60k = 110k > 100k)
        assertFalse(tvlLimit.check(paymentInfo, 60_000e6, payer));
    }

    function test_Check_BlocksWhenEscrowAtLimit() public {
        // Escrow already at limit
        usdc.mint(escrow, LIMIT);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(usdc));

        // Any payment should be blocked
        assertFalse(tvlLimit.check(paymentInfo, 1, payer));
    }

    function test_Check_AllowsZeroAmountPayment() public {
        usdc.mint(escrow, LIMIT);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(usdc));

        // Zero amount should be allowed even at limit
        assertTrue(tvlLimit.check(paymentInfo, 0, payer));
    }

    // ============ Fuzz Tests ============

    function testFuzz_Check_RespectsTvlLimit(uint256 escrowBalance, uint256 paymentAmount) public {
        escrowBalance = bound(escrowBalance, 0, LIMIT * 2);
        paymentAmount = bound(paymentAmount, 0, LIMIT * 2);

        usdc.mint(escrow, escrowBalance);

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(address(usdc));
        bool allowed = tvlLimit.check(paymentInfo, paymentAmount, payer);

        if (escrowBalance + paymentAmount <= LIMIT) {
            assertTrue(allowed, "Should allow when under limit");
        } else {
            assertFalse(allowed, "Should block when over limit");
        }
    }

    function testFuzz_Check_AlwaysBlocksNonUsdc(address token, uint256 amount) public view {
        vm.assume(token != address(usdc));

        AuthCaptureEscrow.PaymentInfo memory paymentInfo = _createPaymentInfo(token);
        assertFalse(tvlLimit.check(paymentInfo, amount, payer));
    }
}
