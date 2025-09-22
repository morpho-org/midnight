// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./interfaces/IMatching.sol";
import "./libraries/ConstantsLib.sol";

contract Matching is IMatching {
    /// FUNCTIONS ///

    function check(Term memory term, uint256 assets, uint256 bonds, Offer memory offer) external view {
        MatchData memory data = abi.decode(offer.matchData, (MatchData));
        require(bonds == assets * (1e18 + (term.maturity - block.timestamp) * data.rate) / 1e18, "bonds");
        require(data.loanToken == term.loanToken, "Loan tokens do not match");
        require(data.maturity == term.maturity, "Maturities do not match");

        Collateral[] memory subset = offer.buying ? term.collaterals : data.collaterals;
        Collateral[] memory superset = offer.buying ? data.collaterals : term.collaterals;

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
