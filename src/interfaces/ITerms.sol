// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

struct Term {
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
    bool buy;
    address offering;
    uint256 assets;
    address loanToken;
    Collateral[] collaterals;
    uint256 maturity;
    uint256 offerStart;
    uint256 offerExpiry;
    // The rate is expressed in percentage per second and is scaled by WAD, so `0.01e18 / uint256(365 days)` represents
    // 1% APR.
    uint256 rate;
    uint256 nonce;
    address callbackAddress;
    bytes callbackData;
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

struct Seizure {
    // Amount of bonds to repay.
    uint256 repaidBonds;
    // Amount of collateral asset to seize.
    uint256 seizedAssets;
}

interface ITerms {}
