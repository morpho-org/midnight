// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {Offer} from "../../interfaces/IMidnight.sol";

struct Take {
    uint256 units;
    Offer offer;
    bytes ratifierData;
    bytes32 root;
    bytes32[] proof;
}

interface ITakeBundler {
    /// ERRORS ///
    error InsufficientLiquidity();
    error Unauthorized();

    // forgefmt: disable-start
    /// FUNCTIONS ///
    function buyUnitsTarget(address midnight, uint256 targetUnits, address taker, address receiverIfTakerIsSeller, Take[] calldata takes) external;
    function buyAssetsTarget(address midnight, uint256 targetBuyerAssets, address taker, address receiverIfTakerIsSeller, Take[] calldata takes) external;
    function sellUnitsTarget(address midnight, uint256 targetUnits, address taker, address receiverIfTakerIsSeller, Take[] calldata takes) external;
    function sellAssetsTarget(address midnight, uint256 targetSellerAssets, address taker, address receiverIfTakerIsSeller, Take[] calldata takes) external;
    // forgefmt: disable-end
}
