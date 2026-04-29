// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IHook} from "../../src/plugins/hooks/IHook.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title MockDataHook
 * @notice Mock hook that stores the last `data` it received for test assertions.
 *         Used to verify that the `data` parameter is correctly forwarded end-to-end
 *         through PaymentOperator to hooks.
 */
contract MockDataHook is IHook {
    /// @notice The last data received by record()
    bytes public lastReceivedData;

    /// @notice Number of times record() was called
    uint256 public recordCount;

    function run(AuthCaptureEscrow.PaymentInfo calldata, uint256, address, bytes calldata data) external {
        lastReceivedData = data;
        recordCount++;
    }
}
