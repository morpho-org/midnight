// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Obligation, CollateralParams} from "../interfaces/IMidnight.sol";
bytes constant COLLATERAL_PARAMS_TYPE = "CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)";
bytes constant OBLIGATION_TYPE =
    "Obligation(address loanToken,CollateralParams[] collateralParams,uint256 maturity,uint256 rcfThreshold,address enterGate,address liquidatorGate)";
bytes constant OFFER_TYPE =
    "Offer(Obligation obligation,bool buy,address maker,uint256 start,uint256 expiry,uint256 tick,bytes32 group,bytes32 session,address callback,bytes callbackData,address receiverIfMakerIsSeller,address ratifier,bool reduceOnly,uint256 maxUnits,uint256 maxSellerAssets,uint256 maxBuyerAssets)";

library SignatureLib {
    function rootTypeHash(uint256 height) internal pure returns (bytes32) {
        bytes memory brackets = new bytes(3 * height);
        for (uint256 i = 0; i < height; i++) {
            brackets[3 * i] = "[";
            brackets[3 * i + 1] = "2";
            brackets[3 * i + 2] = "]";
        }
        return
            keccak256(
                bytes.concat("Root(Offer", brackets, " root)", COLLATERAL_PARAMS_TYPE, OBLIGATION_TYPE, OFFER_TYPE)
            );
    }
}
