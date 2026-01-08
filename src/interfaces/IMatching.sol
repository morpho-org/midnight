// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "./IMorphoV2.sol";

interface IMatching {
    /// @notice Returns the current price for an offer based on time interpolation.
    /// @param offer The offer to compute the price for.
    /// @return price The price in WAD scale (1e18 = 100%).
    function getPrice(Offer memory offer) external view returns (uint256 price);

    /// @notice Converts a tick to a price.
    /// @param tick The tick value.
    /// @return The price in WAD scale.
    function tickToPrice(int256 tick) external view returns (uint256);

    /// @notice Converts a price to a tick within a bounded range.
    /// @param price The price in WAD scale.
    /// @param lowTick The lower tick bound (more negative or smaller positive).
    /// @param highTick The upper tick bound (less negative or larger positive).
    /// @return The tick value.
    function priceToTick(uint256 price, int256 lowTick, int256 highTick) external view returns (int256);
}
