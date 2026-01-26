// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

// Status enum for refund requests: 0 = Pending, 1 = Approved, 2 = Denied, 3 = Cancelled
enum RequestStatus {
    Pending,
    Approved,
    Denied,
    Cancelled
}
