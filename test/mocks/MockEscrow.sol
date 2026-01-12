// SPDX-License-Identifier: MIT
pragma solidity >=0.8.33 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IAuthCaptureEscrow {
    function authorize(
        address payer,
        address merchant,
        address token,
        uint256 amount,
        uint256 expiry,
        address feeRecipient,
        uint256 feeRate,
        bytes calldata collectorData
    ) external returns (bytes32 authorizationId);
    
    function capture(
        bytes32 authorizationId,
        uint256 amount
    ) external;
    
    function refund(
        bytes32 authorizationId,
        address recipient,
        uint256 amount
    ) external;
    
    function void(bytes32 authorizationId) external;
}

/**
 * @title MockEscrow
 * @notice Mock implementation of IAuthCaptureEscrow for testing
 */
contract MockEscrow is IAuthCaptureEscrow {
    using SafeERC20 for IERC20;
    
    struct Authorization {
        address payer;
        address merchant;
        address token;
        uint256 amount;
        uint256 capturedAmount;
        uint256 refundedAmount;
        bool voided;
    }
    
    mapping(bytes32 => Authorization) public authorizations;
    uint256 private nonce;
    
    event Authorized(
        bytes32 indexed authorizationId,
        address indexed payer,
        address indexed merchant,
        address token,
        uint256 amount
    );
    
    event Captured(
        bytes32 indexed authorizationId,
        uint256 amount
    );
    
    event Refunded(
        bytes32 indexed authorizationId,
        address indexed recipient,
        uint256 amount
    );
    
    event Voided(bytes32 indexed authorizationId);
    
    function authorize(
        address payer,
        address merchant,
        address token,
        uint256 amount,
        uint256 /* expiry */,
        address /* feeRecipient */,
        uint256 /* feeRate */,
        bytes calldata /* collectorData */
    ) external returns (bytes32 authorizationId) {
        require(payer != address(0), "Zero payer");
        require(merchant != address(0), "Zero merchant");
        require(token != address(0), "Zero token");
        require(amount > 0, "Zero amount");
        
        // Transfer tokens from payer to this contract
        IERC20(token).safeTransferFrom(payer, address(this), amount);
        
        authorizationId = keccak256(abi.encodePacked(payer, merchant, token, amount, block.timestamp, nonce++));
        
        authorizations[authorizationId] = Authorization({
            payer: payer,
            merchant: merchant,
            token: token,
            amount: amount,
            capturedAmount: 0,
            refundedAmount: 0,
            voided: false
        });
        
        emit Authorized(authorizationId, payer, merchant, token, amount);
    }
    
    function capture(
        bytes32 authorizationId,
        uint256 amount
    ) external {
        Authorization storage auth = authorizations[authorizationId];
        require(auth.payer != address(0), "Authorization does not exist");
        require(!auth.voided, "Authorization voided");
        require(auth.capturedAmount + amount <= auth.amount, "Amount exceeds authorization");
        require(auth.refundedAmount + amount <= auth.amount, "Amount exceeds available");
        
        auth.capturedAmount += amount;
        
        // Calculate fee (simplified - assume fee is deducted from amount)
        uint256 fee = (amount * 50) / 10000; // 0.5 bps
        uint256 merchantAmount = amount - fee;
        
        // Transfer to merchant
        IERC20(auth.token).safeTransfer(auth.merchant, merchantAmount);
        
        // Transfer fee to msg.sender (operator contract)
        if (fee > 0) {
            IERC20(auth.token).safeTransfer(msg.sender, fee);
        }
        
        emit Captured(authorizationId, amount);
    }
    
    function refund(
        bytes32 authorizationId,
        address recipient,
        uint256 amount
    ) external {
        Authorization storage auth = authorizations[authorizationId];
        require(auth.payer != address(0), "Authorization does not exist");
        require(!auth.voided, "Authorization voided");
        require(recipient != address(0), "Zero recipient");
        
        uint256 availableAmount = auth.amount - auth.refundedAmount;
        require(amount <= availableAmount, "Amount exceeds available");
        
        auth.refundedAmount += amount;
        
        // For post-capture refunds, we need to get funds from merchant
        // For pre-capture refunds, funds are still in escrow
        uint256 escrowBalance = IERC20(auth.token).balanceOf(address(this));
        if (escrowBalance < amount) {
            // Post-capture: transfer from merchant back to escrow first
            uint256 needed = amount - escrowBalance;
            IERC20(auth.token).safeTransferFrom(auth.merchant, address(this), needed);
        }
        
        // Transfer back to recipient
        IERC20(auth.token).safeTransfer(recipient, amount);
        
        emit Refunded(authorizationId, recipient, amount);
    }
    
    function void(bytes32 authorizationId) external {
        Authorization storage auth = authorizations[authorizationId];
        require(auth.payer != address(0), "Authorization does not exist");
        require(!auth.voided, "Already voided");
        require(auth.capturedAmount == 0, "Cannot void captured");
        require(auth.refundedAmount == 0, "Cannot void refunded");
        
        auth.voided = true;
        
        // Refund remaining amount to payer
        uint256 remaining = auth.amount - auth.refundedAmount;
        if (remaining > 0) {
            IERC20(auth.token).safeTransfer(auth.payer, remaining);
        }
        
        emit Voided(authorizationId);
    }
    
    // Helper function to get authorization
    function getAuthorization(bytes32 authorizationId) external view returns (Authorization memory) {
        return authorizations[authorizationId];
    }
}

