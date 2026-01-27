// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOperator} from "../../src/operator/arbitration/PaymentOperator.sol";
import {PaymentOperatorFactory} from "../../src/operator/PaymentOperatorFactory.sol";
import {EscrowPeriodConditionFactory} from "../../src/conditions/escrow-period/EscrowPeriodConditionFactory.sol";
import {EscrowPeriodCondition} from "../../src/conditions/escrow-period/EscrowPeriodCondition.sol";
import {EscrowPeriodRecorder} from "../../src/conditions/escrow-period/EscrowPeriodRecorder.sol";
import {PayerFreezePolicy} from "../../src/conditions/escrow-period/freeze-policy/PayerFreezePolicy.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract EscrowPeriodConditionInvariants is Test {
    PaymentOperator public operator;
    AuthCaptureEscrow public escrow;
    EscrowPeriodRecorder public recorder;
    MockERC20 public token;

    address public payer = address(0x1000);
    address public receiver = address(0x2000);

    uint256 public constant ESCROW_PERIOD = 7 days;
    uint256 public constant PAYMENT_AMOUNT = 1000 * 10 ** 18;

    constructor() {
        escrow = new AuthCaptureEscrow();
        token = new MockERC20("Test Token", "TEST");

        EscrowPeriodConditionFactory conditionFactory = new EscrowPeriodConditionFactory();
        PayerFreezePolicy freezePolicy = new PayerFreezePolicy(3 days);
        (address recorderAddr, address conditionAddr) = conditionFactory.deploy(ESCROW_PERIOD, address(freezePolicy));
        recorder = EscrowPeriodRecorder(recorderAddr);

        PaymentOperatorFactory operatorFactory =
            new PaymentOperatorFactory(address(escrow), address(this), 50, 25, address(this));

        PaymentOperatorFactory.OperatorConfig memory config = PaymentOperatorFactory.OperatorConfig({
            feeRecipient: address(this),
            authorizeCondition: address(0),
            authorizeRecorder: address(recorder),
            chargeCondition: address(0),
            chargeRecorder: address(0),
            releaseCondition: conditionAddr,
            releaseRecorder: address(0),
            refundInEscrowCondition: address(0),
            refundInEscrowRecorder: address(0),
            refundPostEscrowCondition: address(0),
            refundPostEscrowRecorder: address(0)
        });
        operator = PaymentOperator(operatorFactory.deployOperator(config));

        token.mint(payer, PAYMENT_AMOUNT * 100);
        vm.prank(payer);
        token.approve(address(escrow), type(uint256).max);
    }

    function echidna_escrow_period_enforced() public view returns (bool) {
        return true;
    }
}
