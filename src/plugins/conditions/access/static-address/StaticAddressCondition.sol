// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

import {ICondition} from "../../ICondition.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title StaticAddressCondition
 * @notice Generic condition that allows only a designated address to call
 * @dev Reusable for any "only X address can call" pattern:
 *      - Arbiter-only actions
 *      - Treasury-only actions
 *      - Service provider-only actions
 *      - Compliance officer-only actions
 *      - DAO multisig-only actions
 */
contract StaticAddressCondition is ICondition {
    /// @notice The designated address allowed to call
    address public immutable DESIGNATED_ADDRESS;

    error ZeroAddress();

    constructor(address _designatedAddress) {
        if (_designatedAddress == address(0)) revert ZeroAddress();
        DESIGNATED_ADDRESS = _designatedAddress;
    }

    /**
     * @notice Check if caller is the designated address
     * @param payment Payment info (not used)
     * @param caller Address attempting the action
     * @return True if caller is the designated address
     */
    function check(AuthCaptureEscrow.PaymentInfo calldata payment, uint256 amount, address caller)
        external
        view
        override
        returns (bool)
    {
        return caller == DESIGNATED_ADDRESS;
    }
}
