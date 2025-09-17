// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

struct Offer {
    address validation;
    bool buy;
    address offering;
    uint256 assets;
    address loanToken;
    uint256 offerStart;
    uint256 offerExpiry;
    uint256 nonce;
    address callbackAddress;
    bytes callbackData;
    bytes offerData; // info about price, collaterals, maturities, which are validated by the validation contract.
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
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
