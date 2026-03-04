// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Midnight} from "../Midnight.sol";
import {Offer} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TickLib} from "../libraries/TickLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";

library TakeAmountsLib {
    using UtilsLib for uint256;

    // Forward: units = shares.mulDivUp/Down(totalUnits + 1, totalShares + 1) depending on buyerIsLender.
    // When buyerIsLender (forward rounds up): inverse rounds down.
    // When !buyerIsLender (forward rounds down): inverse rounds up.
    function unitsToShares(Midnight midnight, bytes20 id, address taker, Offer memory offer, uint256 targetUnits)
        internal
        view
        returns (uint256)
    {
        address buyer = offer.buy ? offer.maker : taker;
        bool buyerIsLender = midnight.debtOf(id, buyer) == 0;
        return buyerIsLender
            ? targetUnits.mulDivDown(midnight.totalShares(id) + 1, midnight.totalUnits(id) + 1)
            : targetUnits.mulDivUp(midnight.totalShares(id) + 1, midnight.totalUnits(id) + 1);
    }

    // Forward: buyerAssets = units.mulDivDown(buyerPrice, WAD).
    /// @dev Should not be used if buyerPrice > WAD, because not all buyerAssets are reachable then.
    function buyerAssetsToShares(
        Midnight midnight,
        bytes20 id,
        address taker,
        Offer memory offer,
        uint256 targetBuyerAssets
    ) internal view returns (uint256) {
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 _tradingFee = midnight.tradingFee(id, UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp));
        uint256 buyerPrice = offer.buy ? offerPrice : offerPrice + _tradingFee;
        require(buyerPrice <= WAD, "buyerPrice");
        uint256 targetUnits = targetBuyerAssets.mulDivUp(WAD, buyerPrice);
        return unitsToShares(midnight, id, taker, offer, targetUnits);
    }

    // Forward: sellerAssets = units.mulDivDown(sellerPrice, WAD).
    function sellerAssetsToShares(
        Midnight midnight,
        bytes20 id,
        address taker,
        Offer memory offer,
        uint256 targetSellerAssets
    ) internal view returns (uint256) {
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 _tradingFee = midnight.tradingFee(id, UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp));
        uint256 sellerPrice = offer.buy ? offerPrice - _tradingFee : offerPrice;
        uint256 targetUnits = targetSellerAssets.mulDivUp(WAD, sellerPrice);
        return unitsToShares(midnight, id, taker, offer, targetUnits);
    }
}
