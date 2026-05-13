// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";

library ConsumableUnitsLib {
    using UtilsLib for uint256;

    /// @dev Returns the number of units that can still be consumed from `offer`.
    /// @dev Assumes that `id` matches `offer.obligation`.
    function consumableUnits(address midnight, bytes32 id, Offer memory offer) internal view returns (uint256) {
        uint256 consumed = IMidnight(midnight).consumed(offer.maker, offer.group);
        if (offer.maxAssets > 0) {
            return offer.buy
                ? TakeAmountsLib.buyerAssetsToUnits(midnight, id, offer, offer.maxAssets.zeroFloorSub(consumed))
                : TakeAmountsLib.sellerAssetsToUnits(midnight, id, offer, offer.maxAssets.zeroFloorSub(consumed));
        } else {
            return offer.maxUnits.zeroFloorSub(consumed);
        }
    }
}
