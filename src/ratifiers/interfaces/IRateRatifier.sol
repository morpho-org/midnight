// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IRatifier} from "../../interfaces/IRatifier.sol";

bytes constant RATE_OFFER_TYPE =
    "RateOffer(Obligation obligation,bool buy,address maker,uint256 start,uint256 expiry,uint256 rate,bytes32 group,bytes32 session,address callback,bytes callbackData,address receiverIfMakerIsSeller,address ratifier,bool reduceOnly,uint256 maxUnits,uint256 maxSellerAssets,uint256 maxBuyerAssets)";
/// @dev keccak256(bytes.concat(RATE_OFFER_TYPE, COLLATERAL_PARAMS_TYPE, OBLIGATION_TYPE))
bytes32 constant RATE_OFFER_TYPEHASH = 0x90e9f9e41e2cb91ddebe5f4e0924a3f0bc32d2c1048017a241339fabf364502c;

interface IRateRatifier is IRatifier {
    /// ERRORS ///
    error InvalidSignature();
    error NotMidnight();
    error Unauthorized();
    error WorsePrice();

    /// STORAGE GETTERS ///
    function MIDNIGHT() external view returns (address);
}
