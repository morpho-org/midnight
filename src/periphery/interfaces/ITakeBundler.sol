// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Offer} from "../../interfaces/IMidnight.sol";

struct Take {
    uint256 units;
    Offer offer;
    bytes sig;
    bytes32 root;
    bytes32[] proof;
}

interface ITakeBundler {
    /// ERRORS ///
    error InsufficientLiquidity();
    error PriceAboveMax();
    error PriceBelowMin();
    error Unauthorized();

    // forgefmt: disable-start
    /// FUNCTIONS ///
    function bundleTakeUnits(address midnight, uint256 targetUnits, address taker, address receiverIfTakerIsSeller, Take[] calldata takes, uint256 minBuyerPrice, uint256 maxBuyerPrice, uint256 minSellerPrice, uint256 maxSellerPrice, bool skipRevertOnPartialFill) external;
    function bundleTakeBuyerAssets(address midnight, uint256 targetBuyerAssets, address taker, address receiverIfTakerIsSeller, Take[] calldata takes, uint256 minPrice, uint256 maxPrice, bool skipRevertOnPartialFill) external;
    function bundleTakeSellerAssets(address midnight, uint256 targetSellerAssets, address taker, address receiverIfTakerIsSeller, Take[] calldata takes, uint256 minPrice, uint256 maxPrice, bool skipRevertOnPartialFill) external;
    // forgefmt: disable-end
}
