// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

abstract contract EscrowAccess {
    address public immutable merchantPayout;
    address public immutable arbiter;

    constructor(address _merchantPayout, address _arbiter) {
        require(_merchantPayout != address(0), "Zero merchant payout");
        require(_arbiter != address(0), "Zero arbiter");
        merchantPayout = _merchantPayout;
        arbiter = _arbiter;
    }

    modifier onlyMerchant() {
        require(msg.sender == merchantPayout, "Not merchant");
        _;
    }

    modifier onlyArbiter() {
        require(msg.sender == arbiter, "Not arbiter");
        _;
    }

    modifier onlyMerchantOrArbiter() {
        require(
            msg.sender == merchantPayout || msg.sender == arbiter,
            "Not merchant or arbiter"
        );
        _;
    }
}

