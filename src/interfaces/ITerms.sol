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
    uint256 price;
    uint256 nonce;
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

struct Seizure {
    // Amount of loan asset to repay.
    uint256 repaidAmount;
    // Amount of collater asset to seize.
    uint256 seizedAssets;
}

interface ITerms {}
