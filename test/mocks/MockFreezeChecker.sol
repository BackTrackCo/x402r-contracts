// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IFreezeChecker} from "../../src/commerce-payments/release-conditions/escrow-period/types/IFreezeChecker.sol";

/**
 * @title MockFreezeChecker
 * @notice Mock implementation of IFreezeChecker for testing
 */
contract MockFreezeChecker is IFreezeChecker {
    mapping(bytes32 => bool) public frozen;

    function freeze(bytes32 paymentInfoHash) external {
        frozen[paymentInfoHash] = true;
    }

    function unfreeze(bytes32 paymentInfoHash) external {
        frozen[paymentInfoHash] = false;
    }

    function isFrozen(bytes32 paymentInfoHash) external view override returns (bool) {
        return frozen[paymentInfoHash];
    }
}
