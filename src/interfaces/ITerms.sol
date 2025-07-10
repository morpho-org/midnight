// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

struct Trade {
    Offer offer;
    bytes check;
}

struct Offer {
    address owner;
    address hook;
    bytes details;
}

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

struct Seizure {
    // Amount of bonds to repay.
    uint256 repaidBonds;
    // Amount of collateral asset to seize.
    uint256 seizedAssets;
}

interface ITerms {}
