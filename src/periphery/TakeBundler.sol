// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {MorphoV2} from "../MorphoV2.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TickLib} from "../libraries/TickLib.sol";
import {IdLib} from "../libraries/IdLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";
import {Offer, Signature} from "../interfaces/IMorphoV2.sol";

struct TakeOrder {
    uint256 maxBuyerAssets;
    uint256 maxSellerAssets;
    uint256 maxObligationUnits;
    uint256 maxObligationShares;
    address takerCallback;
    bytes takerCallbackData;
    address receiverIfTakerIsSeller;
    Offer offer;
    Signature sig;
    bytes32 root;
    bytes32[] proof;
}

/// @dev The four dimensions in which a take can be denominated.
enum FillDimension {
    BuyerAssets,
    SellerAssets,
    ObligationUnits,
    ObligationShares
}

contract TakeBundler {
    using UtilsLib for uint256;

    MorphoV2 public immutable MORPHO;

    constructor(MorphoV2 morpho) {
        MORPHO = morpho;
    }

    function bundleTakeBuyerAssets(uint256 buyerAssets, address taker, TakeOrder[] calldata orders) external {
        _bundleTake(buyerAssets, taker, orders, FillDimension.BuyerAssets);
    }

    function bundleTakeSellerAssets(uint256 sellerAssets, address taker, TakeOrder[] calldata orders) external {
        _bundleTake(sellerAssets, taker, orders, FillDimension.SellerAssets);
    }

    function bundleTakeObligationUnits(uint256 obligationUnits, address taker, TakeOrder[] calldata orders) external {
        _bundleTake(obligationUnits, taker, orders, FillDimension.ObligationUnits);
    }

    function bundleTakeObligationShares(uint256 obligationShares, address taker, TakeOrder[] calldata orders) external {
        _bundleTake(obligationShares, taker, orders, FillDimension.ObligationShares);
    }

    /// @dev Iterates through orders, filling up to `target` in the given dimension.
    function _bundleTake(uint256 target, address taker, TakeOrder[] calldata orders, FillDimension dim) internal {
        require(taker == msg.sender || MORPHO.isAuthorized(taker, msg.sender), "UNAUTHORIZED");

        uint256 filled;

        uint256 i;
        while (i < orders.length && filled < target) {
            uint256 remaining = target - filled;

            (uint256 buyerPrice, uint256 sellerPrice, uint128 totalUnits, uint128 totalShares) =
                _prices(orders[i].offer);

            (uint256 ba, uint256 sa, uint256 ou, uint256 os) =
                _capOrder(remaining, orders[i], dim, buyerPrice, sellerPrice, totalUnits, totalShares);

            try MORPHO.take(
                ba,
                sa,
                ou,
                os,
                taker,
                orders[i].takerCallback,
                orders[i].takerCallbackData,
                orders[i].receiverIfTakerIsSeller,
                orders[i].offer,
                orders[i].sig,
                orders[i].root,
                orders[i].proof
            ) returns (
                uint256 retBa, uint256 retSa, uint256 retOu, uint256 retOs
            ) {
                filled += _selectDimension(dim, retBa, retSa, retOu, retOs);
            } catch {}

            ++i;
        }
    }

    /// @dev Determines which amounts to pass to `take` based on per-order caps and remaining fill target.
    /// Checks the primary dimension cap first, then other dimensions in order (BA, SA, OU, OS).
    /// Uses the first binding cap, or fills the remaining target if no cap is binding.
    function _capOrder(
        uint256 remaining,
        TakeOrder calldata order,
        FillDimension dim,
        uint256 buyerPrice,
        uint256 sellerPrice,
        uint128 totalUnits,
        uint128 totalShares
    ) internal pure returns (uint256 ba, uint256 sa, uint256 ou, uint256 os) {
        uint256 dimIdx = uint256(dim);

        uint256[4] memory caps;
        caps[0] = order.maxBuyerAssets;
        caps[1] = order.maxSellerAssets;
        caps[2] = order.maxObligationUnits;
        caps[3] = order.maxObligationShares;

        // Check primary dimension cap first.
        if (caps[dimIdx] > 0 && remaining > caps[dimIdx]) {
            return _setDimension(dim, caps[dimIdx]);
        }

        // Check other dimension caps in order: BA, SA, OU, OS (skipping primary).
        for (uint256 j; j < 4; ++j) {
            if (j == dimIdx || caps[j] == 0) continue;

            uint256 capInFillDim =
                _convert(caps[j], FillDimension(j), dim, buyerPrice, sellerPrice, totalUnits, totalShares);

            if (remaining > capInFillDim) {
                return _setDimension(FillDimension(j), caps[j]);
            }
        }

        // No cap is binding; fill remaining in the primary dimension.
        return _setDimension(dim, remaining);
    }

    /// @dev Converts `amount` from dimension `from` to dimension `to`.
    function _convert(
        uint256 amount,
        FillDimension from,
        FillDimension to,
        uint256 buyerPrice,
        uint256 sellerPrice,
        uint128 totalUnits,
        uint128 totalShares
    ) internal pure returns (uint256) {
        if (from == FillDimension.BuyerAssets) {
            if (to == FillDimension.SellerAssets) {
                return amount.mulDivDown(sellerPrice, buyerPrice);
            }
            if (to == FillDimension.ObligationUnits) return amount.mulDivDown(WAD, buyerPrice);
            return amount.mulDivDown(WAD, buyerPrice).mulDivDown(totalShares + 1, totalUnits + 1);
        }
        if (from == FillDimension.SellerAssets) {
            if (to == FillDimension.BuyerAssets) return amount.mulDivDown(buyerPrice, sellerPrice);
            if (to == FillDimension.ObligationUnits) return amount.mulDivDown(WAD, sellerPrice);
            return amount.mulDivDown(WAD, sellerPrice).mulDivDown(totalShares + 1, totalUnits + 1);
        }
        if (from == FillDimension.ObligationUnits) {
            if (to == FillDimension.BuyerAssets) return amount.mulDivDown(buyerPrice, WAD);
            if (to == FillDimension.SellerAssets) return amount.mulDivDown(sellerPrice, WAD);
            return amount.mulDivDown(totalShares + 1, totalUnits + 1);
        }
        // from == ObligationShares
        if (to == FillDimension.BuyerAssets) {
            return amount.mulDivDown(totalUnits + 1, totalShares + 1).mulDivDown(buyerPrice, WAD);
        }
        if (to == FillDimension.SellerAssets) {
            return amount.mulDivDown(totalUnits + 1, totalShares + 1).mulDivDown(sellerPrice, WAD);
        }
        return amount.mulDivDown(totalUnits + 1, totalShares + 1);
    }

    /// @dev Returns a tuple with `value` set in the position corresponding to `dim`, and zeros elsewhere.
    function _setDimension(FillDimension dim, uint256 value)
        internal
        pure
        returns (uint256 ba, uint256 sa, uint256 ou, uint256 os)
    {
        if (dim == FillDimension.BuyerAssets) ba = value;
        else if (dim == FillDimension.SellerAssets) sa = value;
        else if (dim == FillDimension.ObligationUnits) ou = value;
        else os = value;
    }

    /// @dev Selects the value corresponding to `dim` from the four return values of `take`.
    function _selectDimension(FillDimension dim, uint256 ba, uint256 sa, uint256 ou, uint256 os)
        internal
        pure
        returns (uint256)
    {
        if (dim == FillDimension.BuyerAssets) return ba;
        if (dim == FillDimension.SellerAssets) return sa;
        if (dim == FillDimension.ObligationUnits) return ou;
        return os;
    }

    function _prices(Offer calldata offer)
        internal
        view
        returns (uint256 buyerPrice, uint256 sellerPrice, uint128 totalUnits, uint128 totalShares)
    {
        bytes32 id = IdLib.toId(offer.obligation, block.chainid, address(MORPHO));
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        uint256 timeToMaturity = UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp);
        uint256 _tradingFee = MORPHO.tradingFee(id, timeToMaturity);
        sellerPrice = offer.buy ? offerPrice - _tradingFee : offerPrice;
        buyerPrice = sellerPrice + _tradingFee;
        (totalUnits, totalShares,,) = MORPHO.obligationState(id);
    }
}
