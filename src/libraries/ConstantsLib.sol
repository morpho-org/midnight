// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

bytes32 constant ORDER_TYPEHASH =
    keccak256("Order(address owner, uint assets, uint bonds, address hook, bytes hookData)");
bytes32 constant OFFER_TYPEHASH = keccak256(
    "Offer(address loanToken, bool buying, bool asBorrower, address owner, uint size, address matching, bytes matchData, address hook, bytes hookData, uint256 nonce, uint256 start, uint256 expiry)"
);
bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
bytes32 constant RATIFICATION_RESPONSE = keccak256("Morpho Market V2 Ratification Response");
