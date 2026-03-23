// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

uint256 constant WAD = 1e18;
uint256 constant ORACLE_PRICE_SCALE = 1e36;
uint256 constant FEE_STEP = 1e12;
uint32 constant MAX_CONTINUOUS_FEE = uint32(uint256(0.01e18) / uint256(365 days));
uint256 constant TIME_TO_MAX_LIF = 15 minutes;
bytes32 constant EIP712_DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
bytes32 constant ROOT_TYPEHASH = keccak256("Root(bytes32 root)");
uint256 constant MAX_COLLATERALS = 128;
uint256 constant MAX_COLLATERALS_PER_BORROWER = 10;
uint256 constant LIQUIDATION_CURSOR_LOW = 0.25e18;
uint256 constant LIQUIDATION_CURSOR_HIGH = 0.5e18;
address constant PASSIVE_FEE_RECIPIENT = address(uint160(uint256(keccak256("passive fee recipient"))));
