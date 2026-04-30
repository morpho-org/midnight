// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

// forgefmt: disable-start
uint256 constant WAD = 1e18;
uint256 constant ORACLE_PRICE_SCALE = 1e36;
uint256 constant FEE_STEP = 1e12;
uint32 constant MAX_CONTINUOUS_FEE = uint32(uint256(0.01e18) / uint256(365 days));
uint256 constant TIME_TO_MAX_LIF = 15 minutes;
uint256 constant MAX_COLLATERALS = 128;
uint256 constant MAX_COLLATERALS_PER_BORROWER = 10;
uint256 constant LIQUIDATION_CURSOR_LOW = 0.25e18;
uint256 constant LIQUIDATION_CURSOR_HIGH = 0.5e18;
uint256 constant LIQUIDATION_LOCK_SLOT = uint256(keccak256("midnight.liquidationLocked"));
bytes32 constant CALLBACK_SUCCESS = keccak256("MIDNIGHT CALLBACK SUCCESS");

bytes constant COLLATERAL_PARAMS_TYPE = "CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)";
/// @dev keccak256(COLLATERAL_PARAMS_TYPE)
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0xaf44a88eb50ebdbbebd980e5a23045c44f61ece5f80ab708a1bbe8718102e6af;
bytes constant OBLIGATION_TYPE = "Obligation(address loanToken,CollateralParams[] collateralParams,uint256 maturity,uint256 rcfThreshold,address enterGate,address liquidatorGate)";
/// @dev keccak256(bytes.concat(OBLIGATION_TYPE, COLLATERAL_PARAMS_TYPE))
bytes32 constant OBLIGATION_TYPEHASH = 0xdcb3d766540d305590a1ee685cb2636a7271c1eea05949c19a23eb48c7492d24;
bytes constant OFFER_TYPE = "Offer(Obligation obligation,bool buy,address maker,uint256 start,uint256 expiry,uint256 tick,bytes32 group,bytes32 session,address callback,bytes callbackData,address receiverIfMakerIsSeller,address ratifier,bool reduceOnly,uint256 maxUnits,uint256 maxSellerAssets,uint256 maxBuyerAssets)";
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, OBLIGATION_TYPE))
bytes32 constant OFFER_TYPEHASH = 0xa75bd7b6468a41ab66f3aa9c068cf8ba48ebfb736e548c3fda0ef0f9e18857a5;

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

/// @dev Returns true if `lltv` is one of the allowed LLTV tiers.
function isLltvAllowed(uint256 lltv) pure returns (bool) {
    return lltv == LLTV_0 || lltv == LLTV_1 || lltv == LLTV_2 || lltv == LLTV_3 || lltv == LLTV_4 || lltv == LLTV_5 || lltv == LLTV_6 || lltv == LLTV_7 || lltv == LLTV_8;
}
// forgefmt: disable-end
