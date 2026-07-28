// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {IBlueBuyCallback} from "./interfaces/IBlueBuyCallback.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";

library ConsumableUnitsLib {
    using UtilsLib for uint128;

    /// @dev Returns a number of units such that it fully consumes the offer.
    /// @dev For a buy offer, caps the result by the callback's `buyerAssetsBound` when the callback exposes it, so that
    /// taking the returned units does not revert in the callback (e.g. withdrawing more than the callback can settle).
    /// @dev Assumes that `id` matches `offer.market`.
    function consumableUnits(address midnight, bytes32 id, Offer memory offer) internal view returns (uint256) {
        uint256 consumed = IMidnight(midnight).consumed(offer.maker, offer.group);
        uint256 units;
        if (offer.maxUnits > 0) {
            units = offer.maxUnits.zeroFloorSub(consumed);
        } else if (offer.buy) {
            units = TakeAmountsLib.buyerAssetsToUnits(midnight, id, offer, offer.maxAssets.zeroFloorSub(consumed));
        } else {
            return TakeAmountsLib.sellerAssetsToUnits(midnight, id, offer, offer.maxAssets.zeroFloorSub(consumed));
        }

        // The bound is optional: fall back to no cap when the callback does not expose `buyerAssetsBound` (the
        // staticcall fails or returns non-32-byte data because the selector is absent).
        if (offer.buy) {
            (bool success, bytes memory returnData) = offer.callback.staticcall(
                abi.encodeCall(IBlueBuyCallback.buyerAssetsBound, (id, offer.market, offer.maker, offer.callbackData))
            );
            if (success && returnData.length == 32) {
                uint256 bound = abi.decode(returnData, (uint256));
                units = UtilsLib.min(units, TakeAmountsLib.unitsFromBuyerAssetsBound(offer, bound));
            }
        }

        return units;
    }
}
