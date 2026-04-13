// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {Midnight} from "../Midnight.sol";
import {Offer} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";

contract TakeBundler {
    using UtilsLib for uint256;

    struct Take {
        uint256 units;
        Offer offer;
        bytes sig;
        bytes32 root;
        bytes32[] proof;
    }

    struct TakeResult {
        uint256 filledBuyerAssets;
        uint256 filledSellerAssets;
        uint256 filledUnits;
        bool success;
    }

    struct BundleTakeUnitsLimits {
        uint256 minBuyerAssets;
        uint256 maxBuyerAssets;
        uint256 minSellerAssets;
        uint256 maxSellerAssets;
    }

    struct BundleTakeAssetsParams {
        uint256 target;
        address taker;
        address receiverIfTakerIsSeller;
        uint256 minResult;
        uint256 maxResult;
    }

    function _computeBuyerUnits(Midnight midnight, bytes32 id, Take calldata take, uint256 remainingBuyerAssets)
        internal
        view
        returns (uint256)
    {
        return UtilsLib.min(TakeAmountsLib.buyerAssetsToUnits(midnight, id, take.offer, remainingBuyerAssets), take.units);
    }

    function _computeSellerUnits(Midnight midnight, bytes32 id, Take calldata take, uint256 remainingSellerAssets)
        internal
        view
        returns (uint256)
    {
        return
            UtilsLib.min(TakeAmountsLib.sellerAssetsToUnits(midnight, id, take.offer, remainingSellerAssets), take.units);
    }

    function _tryTake(
        Midnight midnight,
        uint256 units,
        address taker,
        address receiverIfTakerIsSeller,
        Take calldata take
    ) internal returns (TakeResult memory result) {
        try midnight.take(
            units, taker, address(0), "", receiverIfTakerIsSeller,
            take.offer, take.sig, take.root, take.proof
        ) returns (uint256 filledBuyerAssets, uint256 filledSellerAssets, uint256 filledUnits) {
            result.filledBuyerAssets = filledBuyerAssets;
            result.filledSellerAssets = filledSellerAssets;
            result.filledUnits = filledUnits;
            result.success = true;
        } catch {}
    }

    /// @dev Iterates through orders, filling up to targetUnits units total.
    /// @dev Assumes offers are all buy or all sell and share the same obligation id.
    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    function bundleTakeUnits(
        Midnight midnight,
        uint256 targetUnits,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        BundleTakeUnitsLimits calldata limits
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");

        uint256 totalFilledUnits;
        uint256 totalBuyerAssets;
        uint256 totalSellerAssets;
        for (uint256 i; i < takes.length && totalFilledUnits < targetUnits; i++) {
            TakeResult memory result = _tryTake(
                midnight,
                UtilsLib.min(targetUnits - totalFilledUnits, takes[i].units),
                taker,
                receiverIfTakerIsSeller,
                takes[i]
            );
            if (result.success) {
                totalFilledUnits += result.filledUnits;
                totalBuyerAssets += result.filledBuyerAssets;
                totalSellerAssets += result.filledSellerAssets;
            }
        }

        require(totalFilledUnits == targetUnits, "insufficient liquidity");
        require(totalBuyerAssets >= limits.minBuyerAssets, "buyer assets below min");
        require(totalBuyerAssets <= limits.maxBuyerAssets, "buyer assets above max");
        require(totalSellerAssets >= limits.minSellerAssets, "seller assets below min");
        require(totalSellerAssets <= limits.maxSellerAssets, "seller assets above max");
    }

    /// @dev Same as bundleTakeUnits but targets buyer assets.
    /// @dev Not usable if buyerPrice > WAD, because not all buyerAssets are reachable then.
    /// @dev buyerAssetsToUnits is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    /// @dev Requires a non-empty takes array.
    function bundleTakeBuyerAssets(
        Midnight midnight,
        uint256 targetBuyerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minUnits,
        uint256 maxUnits
    ) external {
        _bundleTakeBuyerAssets(
            midnight,
            takes,
            BundleTakeAssetsParams(targetBuyerAssets, taker, receiverIfTakerIsSeller, minUnits, maxUnits)
        );
    }

    function _bundleTakeBuyerAssets(Midnight midnight, Take[] calldata takes, BundleTakeAssetsParams memory p)
        internal
    {
        require(p.taker == msg.sender || midnight.isAuthorized(p.taker, msg.sender), "unauthorized");
        bytes32 id = midnight.touchObligation(takes[0].offer.obligation);

        uint256 totalFilled;
        uint256 totalUnits;
        for (uint256 i; i < takes.length && totalFilled < p.target; i++) {
            uint256 unitsToTake = _computeBuyerUnits(midnight, id, takes[i], p.target - totalFilled);
            TakeResult memory result = _tryTake(midnight, unitsToTake, p.taker, p.receiverIfTakerIsSeller, takes[i]);
            if (result.success) {
                totalFilled += result.filledBuyerAssets;
                totalUnits += result.filledUnits;
            }
        }

        require(totalFilled == p.target, "insufficient liquidity");
        require(totalUnits >= p.minResult, "units below min");
        require(totalUnits <= p.maxResult, "units above max");
    }

    /// @dev Same as bundleTakeUnits but targets seller assets.
    /// @dev sellerAssetsToUnits is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    /// @dev Requires a non-empty takes array.
    function bundleTakeSellerAssets(
        Midnight midnight,
        uint256 targetSellerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minUnits,
        uint256 maxUnits
    ) external {
        _bundleTakeSellerAssets(
            midnight,
            takes,
            BundleTakeAssetsParams(targetSellerAssets, taker, receiverIfTakerIsSeller, minUnits, maxUnits)
        );
    }

    function _bundleTakeSellerAssets(Midnight midnight, Take[] calldata takes, BundleTakeAssetsParams memory p)
        internal
    {
        require(p.taker == msg.sender || midnight.isAuthorized(p.taker, msg.sender), "unauthorized");
        bytes32 id = midnight.touchObligation(takes[0].offer.obligation);

        uint256 totalFilled;
        uint256 totalUnits;
        for (uint256 i; i < takes.length && totalFilled < p.target; i++) {
            uint256 unitsToTake = _computeSellerUnits(midnight, id, takes[i], p.target - totalFilled);
            TakeResult memory result = _tryTake(midnight, unitsToTake, p.taker, p.receiverIfTakerIsSeller, takes[i]);
            if (result.success) {
                totalFilled += result.filledSellerAssets;
                totalUnits += result.filledUnits;
            }
        }

        require(totalFilled == p.target, "insufficient liquidity");
        require(totalUnits >= p.minResult, "units below min");
        require(totalUnits <= p.maxResult, "units above max");
    }
}
