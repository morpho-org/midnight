// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./interfaces/IValidation.sol";

struct RateOffer {
    uint256 rate;
    Collateral[] collaterals;
}

contract RateOfferValidation is IValidation {
    /// FUNCTIONS ///

    function validate(Term memory term, bytes calldata data) external returns (bool) {
        (RateOffer memory offer) = abi.decode(data, (RateOffer));
        return _checkOffer(term, offer);
        return true;
    }

    /// INTERNAL ///

    function _checkOffer(Term memory term, RateOffer memory offer) internal pure {
        require(offer.maturity == term.maturity, "Maturities do not match");

        // Collateral[] memory subset = offer.buy ? term.collaterals : offer.collaterals;
        // Collateral[] memory superset = offer.buy ? offer.collaterals : term.collaterals;

        // uint256 j = 0;
        // for (uint256 i = 0; i < subset.length; i++) {
        //     // Relies on the fact that the collaterals are sorted.
        //     // Note that we actually never check that.
        //     // If they are not, the matching could fail.
        //     while (superset[j].token != subset[i].token) j++;
        //     require(superset[j].lltv >= subset[i].lltv, "LLTVs do not match");
        //     require(subset[i].oracle == superset[j].oracle, "Oracles do not match");
        //     j++;
        // }
    }
}
