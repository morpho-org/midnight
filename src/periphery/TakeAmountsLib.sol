// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TickLib} from "../libraries/TickLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";

library TakeAmountsLib {
    using UtilsLib for uint256;

    /// @dev Forward mapping rounds buyerAssets down when the maker is the buyer, and up otherwise.
    /// @dev Assumes that id and offer.obligation match.
    /// @dev Reverts if buyerPrice > WAD, because not all buyerAssets are reachable then.
    /// @dev Returns the number of units to take to get the target buyer assets.
    function buyerAssetsToUnits(address midnight, bytes32 id, Offer memory offer, uint256 targetBuyerAssets)
        internal
        view
        returns (uint256)
    {
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 tradingFee =
            IMidnight(midnight).tradingFee(id, UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp));
        uint256 buyerPrice = offer.makerIsBuyer ? offerPrice : offerPrice + tradingFee;
        require(buyerPrice <= WAD, TickLib.PriceGreaterThanOne());
        return offer.makerIsBuyer
            ? targetBuyerAssets.mulDivUp(WAD, buyerPrice)
            : targetBuyerAssets.mulDivDown(WAD, buyerPrice);
    }

    /// @dev Forward mapping rounds sellerAssets down when the maker is the buyer, and up otherwise.
    /// @dev Assumes that id and offer.obligation match.
    /// @dev Returns the number of units to take to get the target seller assets.
    function sellerAssetsToUnits(address midnight, bytes32 id, Offer memory offer, uint256 targetSellerAssets)
        internal
        view
        returns (uint256)
    {
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 tradingFee =
            IMidnight(midnight).tradingFee(id, UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp));
        uint256 sellerPrice = offer.makerIsBuyer ? offerPrice - tradingFee : offerPrice;
        return offer.makerIsBuyer
            ? targetSellerAssets.mulDivUp(WAD, sellerPrice)
            : targetSellerAssets.mulDivDown(WAD, sellerPrice);
    }
}
