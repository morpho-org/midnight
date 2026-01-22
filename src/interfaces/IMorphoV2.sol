// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

struct Obligation {
    address loanToken;
    // Must be sorted by address.
    Collateral[] collaterals;
    uint256 maturity;
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
    uint256 assets;
    uint256 obligationUnits;
    uint256 obligationShares;
    uint256 start;
    uint256 expiry;
    uint256 price;
    bytes32 group;
    bytes32 session;
    address callback;
    bytes callbackData;
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

struct Seizure {
    // Index of the collateral in the obligation's collateral assets.
    uint256 collateralIndex;
    // Amount of obligation units to repay.
    uint256 repaid;
    // Amount of collateral to seize.
    uint256 seized;
}

interface IMorphoV2 {}
