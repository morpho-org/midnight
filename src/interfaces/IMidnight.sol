// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

struct Obligation {
    address loanToken;
    // Must be sorted by address.
    Collateral[] collaterals;
    uint256 maturity;
    // The recovery close factor is deactivated for a collateral if the liquidation could leave a collateral value that
    // would not be enough to repay rcfThreshold units.
    // rcfThreshold is scaled by BALANCE_DECIMALS.
    uint256 rcfThreshold; // 1 rcfThreshold unit = 1e-6 loan token units
}

struct Collateral {
    address token;
    uint256 lltv;
    uint256 maxLif;
    address oracle;
}

struct Offer {
    Obligation obligation;
    bool buy;
    address maker;
    uint256 obligationUnits; // 1 obligation unit = 1e-6 loan token units
    uint256 start;
    uint256 expiry;
    uint256 tick;
    bytes32 group;
    bytes32 session;
    address callback;
    bytes callbackData;
    address receiverIfMakerIsSeller;
    bool exitOnly;
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

struct ObligationState {
    uint128 totalUnits;
    uint256 withdrawable;
    uint128 lossIndex;
    bool created;
    uint16[7] fees;
}

struct Position {
    int256 balance;
    uint128 lossIndex;
    uint128 activatedCollaterals;
    uint128[128] collateral;
}

interface IMidnight {}
