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
uint256 constant TIME_TO_MAX_LIF = 15 minutes;
uint256 constant MAX_COLLATERALS = 128;
uint256 constant MAX_COLLATERALS_PER_BORROWER = 16;
uint256 constant LIQUIDATION_CURSOR_LOW = 0.25e18;
uint256 constant LIQUIDATION_CURSOR_HIGH = 0.5e18;
uint256 constant LIQUIDATION_LOCK_SLOT = uint256(keccak256("morpho.midnight.liquidationLocked"));
bytes32 constant CALLBACK_SUCCESS = keccak256("morpho.midnight.callbackSuccess");
uint8 constant DEFAULT_TICK_SPACING = 4;

/// @dev The allowed LLTV values, copied from Morpho Blue's enabled tiers (excluding zero, including WAD).
uint256 constant LLTV_0 = 0.385e18;
uint256 constant LLTV_1 = 0.625e18;
uint256 constant LLTV_2 = 0.77e18;
uint256 constant LLTV_3 = 0.86e18;
uint256 constant LLTV_4 = 0.915e18;
uint256 constant LLTV_5 = 0.945e18;
uint256 constant LLTV_6 = 0.965e18;
uint256 constant LLTV_7 = 0.98e18;
uint256 constant LLTV_8 = 1e18;

/// @dev Returns true if lltv is one of the allowed LLTV tiers.
function isLltvAllowed(uint256 lltv) pure returns (bool) {
    return lltv == LLTV_0 || lltv == LLTV_1 || lltv == LLTV_2 || lltv == LLTV_3 || lltv == LLTV_4 || lltv == LLTV_5 || lltv == LLTV_6 || lltv == LLTV_7 || lltv == LLTV_8;
}

/// @dev Returns the max settlement fee for the given index.
function maxSettlementFee(uint256 index) pure returns (uint256) {
    return [MAX_SETTLEMENT_FEE_0_DAYS, MAX_SETTLEMENT_FEE_1_DAY, MAX_SETTLEMENT_FEE_7_DAYS, MAX_SETTLEMENT_FEE_30_DAYS, MAX_SETTLEMENT_FEE_90_DAYS, MAX_SETTLEMENT_FEE_180_DAYS, MAX_SETTLEMENT_FEE_360_DAYS][index];
}

/// @dev Returns the max LIF for the given lltv and cursor.
function maxLif(uint256 lltv, uint256 cursor) pure returns (uint256) {
    return UtilsLib.mulDivDown(WAD, WAD, WAD - UtilsLib.mulDivDown(cursor, WAD - lltv, WAD));
}
// forgefmt: disable-end
