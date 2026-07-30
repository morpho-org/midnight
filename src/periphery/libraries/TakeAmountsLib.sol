// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IMidnight, Offer} from "../../interfaces/IMidnight.sol";
import {UtilsLib} from "../../libraries/UtilsLib.sol";
import {TickLib} from "../../libraries/TickLib.sol";
import {WAD} from "../../libraries/ConstantsLib.sol";

library TakeAmountsLib {
    using UtilsLib for uint256;

    /// @dev Forward: buyerAssets = offer.buy ? units.mulDivDown(buyerPrice, WAD) : units.mulDivUp(buyerPrice, WAD).
    /// @dev Assumes that id and offer.market match.
    /// @dev Reverts if buyerPrice > WAD, because not all buyerAssets are reachable then.
    /// @dev Reverts if offerPrice < settlementFee in case of a buy offer (midnight reverts too).
    /// @dev Returns units (not necessarily the smallest/biggest) for which take yields exactly targetBuyerAssets.
    function buyerAssetsToUnits(address midnight, bytes32 id, Offer memory offer, uint256 targetBuyerAssets)
        internal
        view
        returns (uint256)
    {
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 settlementFee =
            IMidnight(midnight).settlementFee(id, UtilsLib.zeroFloorSub(offer.market.maturity, block.timestamp));
        // Mirrors Midnight's computation to revert if offerPrice < settlementFee in case of a buy offer.
        uint256 sellerPrice = offer.buy ? offerPrice - settlementFee : offerPrice;
        uint256 buyerPrice = sellerPrice + settlementFee;
        require(buyerPrice <= WAD, TickLib.PriceGreaterThanOne());
        return offer.buy ? targetBuyerAssets.mulDivUp(WAD, buyerPrice) : targetBuyerAssets.mulDivDown(WAD, buyerPrice);
    }

    /// @dev Forward: sellerAssets = offer.buy ? units.mulDivDown(sellerPrice, WAD) : units.mulDivUp(sellerPrice, WAD).
    /// @dev Assumes that id and offer.market match.
    /// @dev Reverts if offerPrice < settlementFee in case of a buy offer (midnight reverts too).
    /// @dev Returns units (not necessarily the smallest/biggest) for which take yields exactly targetSellerAssets.
    function sellerAssetsToUnits(address midnight, bytes32 id, Offer memory offer, uint256 targetSellerAssets)
        internal
        view
        returns (uint256)
    {
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 settlementFee =
            IMidnight(midnight).settlementFee(id, UtilsLib.zeroFloorSub(offer.market.maturity, block.timestamp));
        uint256 sellerPrice = offer.buy ? offerPrice - settlementFee : offerPrice;
        return
            offer.buy ? targetSellerAssets.mulDivUp(WAD, sellerPrice) : targetSellerAssets.mulDivDown(WAD, sellerPrice);
    }

    /// @dev Returns the largest number of units whose take settles at most `buyerAssetsBound` buyer assets.
    /// @dev buyerPrice equals offerPrice for a buy offer (sellerPrice + settlementFee), so no settlement fee is needed.
    /// @dev Rounds down (unlike `buyerAssetsToUnits`) so that the buyer assets settled for the returned units, i.e.
    /// units.mulDivDown(offerPrice, WAD), never exceed `buyerAssetsBound`.
    /// @dev Assumes that offer.buy is true.
    function unitsFromBuyerAssetsBound(Offer memory offer, uint256 buyerAssetsBound) internal pure returns (uint256) {
        return buyerAssetsBound.mulDivDown(WAD, TickLib.tickToPrice(offer.tick));
    }
}
