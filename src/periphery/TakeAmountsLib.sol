// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TickLib} from "../libraries/TickLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";

library TakeAmountsLib {
    using UtilsLib for uint256;

    /// @dev Forward: buyerAssets = offer.buy ? units.mulDivDown(buyerPrice, WAD) : units.mulDivUp(buyerPrice, WAD).
    /// @dev Assumes that id and offer.market match.
    /// @dev Reverts if buyerPrice > WAD, because not all buyerAssets are reachable then.
    /// @dev Reverts if offerPrice < tradingFee in case of a buy offer (midnight reverts too).
    /// @dev Returns a number of units to take to get the target buyer assets.
    function buyerAssetsToUnits(address midnight, bytes32 id, Offer memory offer, uint256 targetBuyerAssets)
        internal
        view
        returns (uint256)
    {
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 tradingFee =
            IMidnight(midnight).tradingFee(id, UtilsLib.zeroFloorSub(offer.market.maturity, block.timestamp));
        // Mirrors Midnight's computation to revert if offerPrice < tradingFee in case of a buy offer.
        uint256 sellerPrice = offer.buy ? offerPrice - tradingFee : offerPrice;
        uint256 buyerPrice = sellerPrice + tradingFee;
        require(buyerPrice <= WAD, TickLib.PriceGreaterThanOne());
        return offer.buy ? targetBuyerAssets.mulDivUp(WAD, buyerPrice) : targetBuyerAssets.mulDivDown(WAD, buyerPrice);
    }

    /// @dev Forward: sellerAssets = offer.buy ? units.mulDivDown(sellerPrice, WAD) : units.mulDivUp(sellerPrice, WAD).
    /// @dev Assumes that id and offer.market match.
    /// @dev Reverts if offerPrice < tradingFee in case of a buy offer (midnight reverts too).
    /// @dev Returns a number of units to take to get the target seller assets.
    function sellerAssetsToUnits(address midnight, bytes32 id, Offer memory offer, uint256 targetSellerAssets)
        internal
        view
        returns (uint256)
    {
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 tradingFee =
            IMidnight(midnight).tradingFee(id, UtilsLib.zeroFloorSub(offer.market.maturity, block.timestamp));
        uint256 sellerPrice = offer.buy ? offerPrice - tradingFee : offerPrice;
        return
            offer.buy ? targetSellerAssets.mulDivUp(WAD, sellerPrice) : targetSellerAssets.mulDivDown(WAD, sellerPrice);
    }
}
