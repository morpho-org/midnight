// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Midnight} from "../Midnight.sol";
import {Offer} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TickLib} from "../libraries/TickLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";

library TakeAmountsLib {
    using UtilsLib for uint256;

    // Forward: buyerAssets = offer.buy ? units.mulDivDown(buyerPrice, WAD) : units.mulDivUp(buyerPrice, WAD),
    // where the trading fee is the rounded-up value returned by Midnight. If tradingFee > 0 and offer.buy is false,
    // buyerAssets is incremented by 1 when it would otherwise equal sellerAssets.
    /// @dev Reverts if buyerPrice > WAD, because not all buyerAssets are reachable then.
    /// @dev Returns the number of units to take to get the target buyer assets.
    function buyerAssetsToUnits(Midnight midnight, bytes32 id, Offer memory offer, uint256 targetBuyerAssets)
        internal
        view
        returns (uint256)
    {
        if (targetBuyerAssets == 0) return 0;
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 tradingFee = midnight.tradingFee(id, UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp));
        uint256 sellerPrice = offer.buy ? offerPrice - tradingFee : offerPrice;
        uint256 buyerPrice = offer.buy ? offerPrice : offerPrice + tradingFee;
        require(buyerPrice <= WAD, "buyerPrice");
        if (offer.buy) return targetBuyerAssets.mulDivUp(WAD, buyerPrice);
        if (tradingFee == 0) return targetBuyerAssets.mulDivDown(WAD, buyerPrice);

        uint256 unitsToReachBuyerAssets = targetBuyerAssets.zeroFloorSub(1).mulDivDown(WAD, buyerPrice) + 1;
        if (targetBuyerAssets > 1 && sellerPrice > 0) {
            uint256 unitsToReachSellerAssetsPlusOne =
                (targetBuyerAssets - 1).zeroFloorSub(1).mulDivDown(WAD, sellerPrice) + 1;
            unitsToReachBuyerAssets = UtilsLib.min(unitsToReachBuyerAssets, unitsToReachSellerAssetsPlusOne);
        }

        uint256 buyerAssets = unitsToReachBuyerAssets.mulDivUp(buyerPrice, WAD);
        if (buyerAssets == unitsToReachBuyerAssets.mulDivUp(sellerPrice, WAD)) buyerAssets++;
        require(buyerAssets == targetBuyerAssets, "buyerAssets");
        return unitsToReachBuyerAssets;
    }

    // Forward: sellerAssets = offer.buy ? units.mulDivDown(sellerPrice, WAD) : units.mulDivUp(sellerPrice, WAD),
    // where the trading fee is the rounded-up value returned by Midnight. If tradingFee > 0 and offer.buy is true,
    // sellerAssets is decremented by 1, floored at 0, when it would otherwise equal buyerAssets.
    /// @dev Returns the number of units to take to get the target seller assets.
    function sellerAssetsToUnits(Midnight midnight, bytes32 id, Offer memory offer, uint256 targetSellerAssets)
        internal
        view
        returns (uint256)
    {
        if (targetSellerAssets == 0) return 0;
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 tradingFee = midnight.tradingFee(id, UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp));
        uint256 sellerPrice = offer.buy ? offerPrice - tradingFee : offerPrice;
        if (!offer.buy) return targetSellerAssets.mulDivDown(WAD, sellerPrice);
        if (tradingFee == 0) return targetSellerAssets.mulDivUp(WAD, sellerPrice);

        uint256 unitsToReachSellerAssets = targetSellerAssets.mulDivUp(WAD, sellerPrice);
        uint256 unitsToReachBuyerAssetsPlusOne = (targetSellerAssets + 1).mulDivUp(WAD, offerPrice);
        return unitsToReachSellerAssets > unitsToReachBuyerAssetsPlusOne
            ? unitsToReachSellerAssets
            : unitsToReachBuyerAssetsPlusOne;
    }
}
