// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IFreezePolicy} from "../../src/commerce-payments/hooks/escrow-period/types/IFreezePolicy.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title MockFreezePolicy
 * @notice Mock implementation of IFreezePolicy for testing
 * @dev Always allows freeze/unfreeze - useful for testing freeze mechanics
 */
contract MockFreezePolicy is IFreezePolicy {
    bool public allowFreeze = true;
    bool public allowUnfreeze = true;

    function setAllowFreeze(bool _allow) external {
        allowFreeze = _allow;
    }

    function setAllowUnfreeze(bool _allow) external {
        allowUnfreeze = _allow;
    }

    function canFreeze(
        AuthCaptureEscrow.PaymentInfo calldata,
        address
    ) external view override returns (bool) {
        return allowFreeze;
    }

    function canUnfreeze(
        AuthCaptureEscrow.PaymentInfo calldata,
        address
    ) external view override returns (bool) {
        return allowUnfreeze;
    }
}
