// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

abstract contract EscrowAccess {
    address public immutable MERCHANT_PAYOUT;
    address public immutable ARBITER;

    constructor(address _merchantPayout, address _arbiter) {
        require(_merchantPayout != address(0), "Zero merchant payout");
        require(_arbiter != address(0), "Zero arbiter");
        MERCHANT_PAYOUT = _merchantPayout;
        ARBITER = _arbiter;
    }

    modifier onlyMerchant() {
        _onlyMerchant();
        _;
    }

    function _onlyMerchant() internal view {
        require(msg.sender == MERCHANT_PAYOUT, "Not merchant");
    }

    modifier onlyArbiter() {
        _onlyArbiter();
        _;
    }

    function _onlyArbiter() internal view {
        require(msg.sender == ARBITER, "Not arbiter");
    }

    modifier onlyMerchantOrArbiter() {
        _onlyMerchantOrArbiter();
        _;
    }

    function _onlyMerchantOrArbiter() internal view {
        require(
            msg.sender == MERCHANT_PAYOUT || msg.sender == ARBITER,
            "Not merchant or arbiter"
        );
    }
}

