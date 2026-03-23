// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Midnight} from "../Midnight.sol";
import {Offer} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TickLib} from "../libraries/TickLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";

library TakeAmountsLib {
    using UtilsLib for uint256;

    // Forward: buyerAssets = offer.buy ? units.mulDivDown(buyerPrice, WAD) : units.mulDivUp(buyerPrice, WAD).
    /// @dev Reverts if buyerPrice > WAD, because not all buyerAssets are reachable then.
    /// @dev Returns the number of units to take to get the target buyer assets.
    function buyerAssetsToUnits(Midnight midnight, bytes32 id, Offer memory offer, uint256 targetBuyerAssets)
        internal
        view
        returns (uint256)
    {
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 tradingFee = midnight.tradingFee(id, UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp));
        uint256 buyerPrice = offer.buy ? offerPrice : offerPrice + tradingFee;
        require(buyerPrice <= WAD, "buyerPrice");
        return offer.buy ? targetBuyerAssets.mulDivUp(WAD, buyerPrice) : targetBuyerAssets.mulDivDown(WAD, buyerPrice);
    }

    // Forward: sellerAssets = offer.buy ? units.mulDivDown(sellerPrice, WAD) : units.mulDivUp(sellerPrice, WAD).
    /// @dev Returns the number of units to take to get the target seller assets.
    function sellerAssetsToUnits(Midnight midnight, bytes32 id, Offer memory offer, uint256 targetSellerAssets)
        internal
        view
        returns (uint256)
    {
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 tradingFee = midnight.tradingFee(id, UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp));
        uint256 sellerPrice = offer.buy ? offerPrice - tradingFee : offerPrice;
        return
            offer.buy ? targetSellerAssets.mulDivUp(WAD, sellerPrice) : targetSellerAssets.mulDivDown(WAD, sellerPrice);
    }
}
