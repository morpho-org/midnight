// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {UtilsLib} from "./UtilsLib.sol";

// forgefmt: disable-start
uint256 constant WAD = 1e18;
uint256 constant ORACLE_PRICE_SCALE = 1e36;
uint256 constant CBP = 1e12;
uint256 constant MAX_SETTLEMENT_FEE_0_DAYS = 0.000014e18;
uint256 constant MAX_SETTLEMENT_FEE_1_DAY = 0.000014e18;
uint256 constant MAX_SETTLEMENT_FEE_7_DAYS = 0.000098e18;
uint256 constant MAX_SETTLEMENT_FEE_30_DAYS = 0.000417e18;
uint256 constant MAX_SETTLEMENT_FEE_90_DAYS = 0.00125e18;
uint256 constant MAX_SETTLEMENT_FEE_180_DAYS = 0.0025e18;
uint256 constant MAX_SETTLEMENT_FEE_360_DAYS = 0.005e18;
uint32 constant MAX_CONTINUOUS_FEE = uint32(uint256(0.01e18) / uint256(365 days));
uint256 constant TIME_TO_MAX_LIF = 60 minutes;
uint256 constant MAX_COLLATERALS = 128;
uint256 constant MAX_COLLATERALS_PER_BORROWER = 16;
uint256 constant LIQUIDATION_LOCK_SLOT = uint256(keccak256("morpho.midnight.liquidationLocked"));
bytes32 constant CALLBACK_SUCCESS = keccak256("morpho.midnight.callbackSuccess");
uint8 constant DEFAULT_TICK_SPACING = 4;

/// @dev Returns the max settlement fee for the given index.
function maxSettlementFee(uint256 index) pure returns (uint256) {
    return [MAX_SETTLEMENT_FEE_0_DAYS, MAX_SETTLEMENT_FEE_1_DAY, MAX_SETTLEMENT_FEE_7_DAYS, MAX_SETTLEMENT_FEE_30_DAYS, MAX_SETTLEMENT_FEE_90_DAYS, MAX_SETTLEMENT_FEE_180_DAYS, MAX_SETTLEMENT_FEE_360_DAYS][index];
}

/// @dev Returns the max LIF for the given lltv and liquidationCursor.
function maxLif(uint256 lltv, uint256 liquidationCursor) pure returns (uint256) {
    return UtilsLib.mulDivDown(WAD, WAD, WAD - UtilsLib.mulDivDown(liquidationCursor, WAD - lltv, WAD));
}
// forgefmt: disable-end
