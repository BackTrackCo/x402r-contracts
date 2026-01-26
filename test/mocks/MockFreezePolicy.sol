// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IFreezePolicy} from "../../src/conditions/escrow-period/freeze-policy/IFreezePolicy.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title MockFreezePolicy
 * @notice Mock implementation of IFreezePolicy for testing
 * @dev Configurable freeze/unfreeze permissions and duration
 */
contract MockFreezePolicy is IFreezePolicy {
    bool public allowFreeze = true;
    bool public allowUnfreeze = true;
    uint256 public freezeDuration = 0; // 0 = permanent

    function setAllowFreeze(bool _allow) external {
        allowFreeze = _allow;
    }

    function setAllowUnfreeze(bool _allow) external {
        allowUnfreeze = _allow;
    }

    function setFreezeDuration(uint256 _duration) external {
        freezeDuration = _duration;
    }

    function canFreeze(AuthCaptureEscrow.PaymentInfo calldata, address)
        external
        view
        override
        returns (bool allowed, uint256 duration)
    {
        allowed = allowFreeze;
        duration = freezeDuration;
    }

    function canUnfreeze(AuthCaptureEscrow.PaymentInfo calldata, address) external view override returns (bool) {
        return allowUnfreeze;
    }
}
