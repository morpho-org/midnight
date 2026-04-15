// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Midnight} from "../../Midnight.sol";
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
    error BuyerAssetsAboveMax();
    error BuyerAssetsBelowMin();
    error InsufficientLiquidity();
    error SellerAssetsAboveMax();
    error SellerAssetsBelowMin();
    error Unauthorized();
    error UnitsAboveMax();
    error UnitsBelowMin();

    // forgefmt: disable-start
    /// FUNCTIONS ///
    function bundleTakeUnits(Midnight midnight, uint256 targetUnits, address taker, address receiverIfTakerIsSeller, Take[] calldata takes, uint256 minBuyerAssets, uint256 maxBuyerAssets, uint256 minSellerAssets, uint256 maxSellerAssets) external;
    function bundleTakeBuyerAssets(Midnight midnight, uint256 targetBuyerAssets, address taker, address receiverIfTakerIsSeller, Take[] calldata takes, uint256 minUnits, uint256 maxUnits) external;
    function bundleTakeSellerAssets(Midnight midnight, uint256 targetSellerAssets, address taker, address receiverIfTakerIsSeller, Take[] calldata takes, uint256 minUnits, uint256 maxUnits) external;
    // forgefmt: disable-end
}
