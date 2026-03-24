// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRecorder} from "../../src/plugins/recorders/IRecorder.sol";
import {AuthCaptureEscrow} from "commerce-payments/AuthCaptureEscrow.sol";

/**
 * @title MockDataRecorder
 * @notice Mock recorder that stores the last `data` it received for test assertions.
 *         Used to verify that the `data` parameter is correctly forwarded end-to-end
 *         through PaymentOperator to recorders.
 */
contract MockDataRecorder is IRecorder {
    /// @notice The last data received by record()
    bytes public lastReceivedData;

    /// @notice Number of times record() was called
    uint256 public recordCount;

    function record(AuthCaptureEscrow.PaymentInfo calldata, uint256, address, bytes calldata data) external {
        lastReceivedData = data;
        recordCount++;
    }
}
