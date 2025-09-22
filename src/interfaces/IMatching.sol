// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import "./ITerms.sol";

struct MatchData {
    address loanToken;
    Collateral[] collaterals;
    uint256 maturity;
    // The rate is expressed in percentage per second and is scaled by WAD, so `0.01e18 / uint256(365 days)` represents
    // 1% APR.
    uint256 rate;
}

interface IMatching {
    function check(Term memory term, uint256 assets, uint256 bonds, Offer memory offer) external;
}
