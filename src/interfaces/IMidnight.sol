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
    uint256 rcfThreshold;
}

struct Collateral {
    address token;
    uint256 lltv;
    address oracle;
}

struct Offer {
    Obligation obligation;
    bool buy;
    address maker;
    uint256 obligationUnits;
    uint256 obligationShares;
    uint256 start;
    uint256 expiry;
    uint256 tick;
    bytes32 group;
    bytes32 session;
    address callback;
    bytes callbackData;
    address receiverIfMakerIsSeller;
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

struct BorrowerState {
    uint128 debt;
    uint128 activatedCollaterals;
}

struct ObligationState {
    uint128 totalUnits;
    uint128 totalShares;
    uint256 withdrawable;
    bool created;
    uint16[7] fees;
}

interface IMidnight {}
