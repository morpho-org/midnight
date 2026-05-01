// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TickLib} from "../libraries/TickLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";

library TakeAmountsLib {
    using UtilsLib for uint256;

    /// @dev Returns the largest number of units such that take gives `targetBuyerAssets`.
    /// @dev Reverts if buyerPrice > WAD, because not all buyerAssets are reachable then.
    function buyerAssetsToUnits(address midnight, bytes32 id, Offer memory offer, uint256 targetBuyerAssets)
        internal
        view
        returns (uint256)
    {
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 tradingFee =
            IMidnight(midnight).tradingFee(id, UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp));
        uint256 buyerPrice = offer.buy ? offerPrice : offerPrice + tradingFee;
        require(buyerPrice <= WAD, TickLib.PriceGreaterThanOne());
        return offer.buy
            ? ((targetBuyerAssets + 1) * WAD - 1).mulDivDown(1, buyerPrice)
            : targetBuyerAssets.mulDivDown(WAD, buyerPrice);
    }

    /// @dev Returns the smallest number of units such that take gives `targetSellerAssets`.
    function sellerAssetsToUnits(address midnight, bytes32 id, Offer memory offer, uint256 targetSellerAssets)
        internal
        view
        returns (uint256)
    {
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 tradingFee =
            IMidnight(midnight).tradingFee(id, UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp));
        uint256 sellerPrice = offer.buy ? offerPrice - tradingFee : offerPrice;
        return offer.buy
            ? targetSellerAssets.mulDivUp(WAD, sellerPrice)
            : ((targetSellerAssets - 1) * WAD + 1).mulDivUp(1, sellerPrice);
    }
}
