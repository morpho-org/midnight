// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

uint256 constant WAD = 1e18;
uint256 constant ORACLE_PRICE_SCALE = 1e36;
uint256 constant MAX_LIF = 1.15e18; // Liquidation Incentive Factor
uint256 constant TIME_TO_MAX_LIF = 15 minutes; // Time to reach MAX_LIF
