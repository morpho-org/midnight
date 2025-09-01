// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @dev The prefix for the imbalance slot.
bytes32 constant IMBALANCE_PREFIX = keccak256("imbalance");

/// @dev The prefix for the maybe unhealthy slot.
bytes32 constant MAYBE_UNHEALTHY_PREFIX = keccak256("maybe unhealthy");

bytes32 constant OFFER_TYPEHASH = keccak256("Offer(bool buy, address offering, bytes data, bytes validation)");
