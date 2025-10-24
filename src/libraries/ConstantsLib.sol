// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
bytes32 constant AUTHORIZATION_TYPEHASH =
    keccak256("Authorization(address authorizer,address authorizee,bool authorized,uint256 nonce,uint256 deadline)");
uint256 constant WAD = 1e18;
uint256 constant ORACLE_PRICE_SCALE = 1e36;
uint256 constant LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;
