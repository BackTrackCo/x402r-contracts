// SPDX-License-Identifier: BUSL-1.1
// CONTRACTS UNAUDITED: USE AT YOUR OWN RISK
pragma solidity ^0.8.28;

// ============ Registry Events ============
event ArbiterRegistered(address indexed arbiter, string uri);
event ArbiterUriUpdated(address indexed arbiter, string oldUri, string newUri);
event ArbiterDeregistered(address indexed arbiter);
