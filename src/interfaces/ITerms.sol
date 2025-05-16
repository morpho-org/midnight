// SPDX-License-Identifier: UNLICENSED
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

struct Callback {
    address callbackAddress;
    bytes callbackData;
    uint256 callbackGasLimit;
}

struct Offer {
    bool buy;
    address offering;
    uint256 assets;
    address loanToken;
    Collateral[] collaterals;
    uint256 maturity;
    uint256 price;
    Callback callback;
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

interface ITerms {}
