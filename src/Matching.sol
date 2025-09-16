// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./interfaces/IMatching.sol";
import "./libraries/ConstantsLib.sol";

struct MatchingData {
    bool buying;
    uint256 assets;
    address loanToken;
    Collateral[] collaterals;
    uint256 maturity;
    // The rate is expressed in percentage per second and is scaled by WAD, so `0.01e18 / uint256(365 days)` represents
    // 1% APR.
    uint256 rate;
    uint256 nonce;
}

contract Matching is IMatching {
    /// STORAGE ///

    /// @dev Multiple offers can have the same nonce. This allows to implement easy and efficient batch-cancelling and
    /// OCO (One-Cancels-the-Other) orders. Note that OCO orders work better if all offers have the same amount,
    /// otherwise one might not be takable anymore while an other one at the same nonce is still takeable.
    mapping(address user => mapping(uint256 nonce => uint256)) public consumed;

    /// FUNCTIONS ///

    function check(Term memory term, uint256 assets, uint256 bonds, Make memory make) external {
        MatchingData memory data = abi.decode(make.matchingData, (MatchingData));
        consumed[make.owner][data.nonce] += assets;
        require(consumed[make.owner][data.nonce] <= data.assets, "consumed");
        require(bonds == assets * (1e18 + (term.maturity - block.timestamp) * data.rate) / 1e18, "bonds");
        require(data.loanToken == term.loanToken, "Loan tokens do not match");
        require(data.maturity == term.maturity, "Maturities do not match");

        Collateral[] memory subset = data.buying ? term.collaterals : data.collaterals;
        Collateral[] memory superset = data.buying ? data.collaterals : term.collaterals;

        uint256 j = 0;
        for (uint256 i = 0; i < subset.length; i++) {
            // Relies on the fact that the collaterals are sorted.
            // Note that we actually never check that.
            // If they are not, the matching could fail.
            while (superset[j].token != subset[i].token) j++;
            require(superset[j].lltv >= subset[i].lltv, "LLTVs do not match");
            require(subset[i].oracle == superset[j].oracle, "Oracles do not match");
            j++;
        }
    }
}
