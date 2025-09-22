// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

struct Order {
    address owner;
    uint256 assets;
    uint256 bonds;
    address hook;
    bytes hookData;
}

// Buying as a borrower is repaying.
// Buying as a lender is lending.
// Selling as a borrower is borrowing.
// Selling as a lender is withdrawing.
struct Offer {
    bool buying;
    bool asBorrower;
    address owner;
    uint256 assets;
    address matching;
    bytes matchData;
    address hook;
    bytes hookData;
    uint256 nonce;
    uint256 start;
    uint256 expiry;
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

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}
