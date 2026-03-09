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
    function unitsToShares(Midnight midnight, bytes32 id, address taker, Offer memory offer, uint256 targetUnits)
        internal
        view
        returns (uint256)
    {
        address buyer = offer.buy ? offer.maker : taker;
        bool buyerIsLender = midnight.debtOf(id, buyer) == 0;
        (uint256 adjustedTotalUnits, uint256 adjustedTotalShares) =
            _totalsAfterFeeAccrual(midnight, id, taker, offer.maker, offer.obligation.maturity);
        return buyerIsLender
            ? targetUnits.mulDivDown(adjustedTotalShares + 1, adjustedTotalUnits + 1)
            : targetUnits.mulDivUp(adjustedTotalShares + 1, adjustedTotalUnits + 1);
    }

    /// @dev Simulates accrueContinuousFee for both taker and maker (in that order, matching take()),
    /// returning the adjusted totalUnits and totalShares.
    function _totalsAfterFeeAccrual(Midnight midnight, bytes32 id, address taker, address maker, uint256 maturity)
        private
        view
        returns (uint256 totalUnits, uint256 totalShares)
    {
        totalUnits = midnight.totalUnits(id);
        totalShares = midnight.totalShares(id);
        address _feeRecipient = midnight.feeRecipient();
        bool feeRecipientIsLender = midnight.debtOf(id, _feeRecipient) == 0;

        (totalUnits, totalShares) =
            _simulateAccrual(midnight, id, taker, maturity, totalUnits, totalShares, feeRecipientIsLender);
        (totalUnits, totalShares) =
            _simulateAccrual(midnight, id, maker, maturity, totalUnits, totalShares, feeRecipientIsLender);
    }

    function _simulateAccrual(
        Midnight midnight,
        bytes32 id,
        address user,
        uint256 maturity,
        uint256 totalUnits,
        uint256 totalShares,
        bool feeRecipientIsLender
    ) private view returns (uint256, uint256) {
        uint256 remaining = midnight.pendingFee(id, user);
        uint256 lastAccrual = midnight.lastContinuousFeeAccrual(id, user);

        if (remaining > 0 && lastAccrual > 0) {
            uint256 feeUnits;
            if (block.timestamp >= maturity) {
                feeUnits = remaining;
            } else {
                uint256 elapsed = block.timestamp - lastAccrual;
                feeUnits = remaining.mulDivDown(elapsed, maturity - lastAccrual);
            }

            if (feeUnits > 0 && feeRecipientIsLender) {
                uint256 feeShares = feeUnits.mulDivDown(totalShares + 1, totalUnits + 1);
                totalUnits += feeUnits;
                totalShares += feeShares;
            }
        }

        return (totalUnits, totalShares);
    }

    // Forward: buyerAssets = units.mulDivDown(buyerPrice, WAD).
    /// @dev Should not be used if buyerPrice > WAD, because not all buyerAssets are reachable then.
    function buyerAssetsToShares(
        Midnight midnight,
        bytes32 id,
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
        bytes32 id,
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
