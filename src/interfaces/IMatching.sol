// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./ITerms.sol";

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

interface IMatching {
    function take(Term memory term, uint256 assets, bytes calldata data)
        external
        returns (
            bool buy,
            address counterparty,
            uint256 bonds,
            address makerCallbackAddress,
            bytes memory makerCallbackData
        );
}
