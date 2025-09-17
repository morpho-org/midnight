// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

bytes32 constant TAKE_TYPEHASH = keccak256("Take(address owner, uint assets, uint bonds, address hook, bytes hookData)");
bytes32 constant MAKE_TYPEHASH = keccak256(
    "Make(address loanToken, bool buying, address owner, address matching, bytes matchingData, address hook, bytes hookData)"
);
bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
bytes32 constant HOOK_SUCCESS = keccak256("Morpho Market V2 Hook Success");
