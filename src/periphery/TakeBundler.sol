// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {Midnight} from "../Midnight.sol";
import {Offer, Signature} from "../interfaces/IMidnight.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";

contract TakeBundler {
    using UtilsLib for uint256;

    struct Take {
        uint256 obligationShares;
        Offer offer;
        Signature sig;
        bytes32 root;
        bytes32[] proof;
    }

    /// @dev Iterates through orders, filling up to `targetShares` obligation shares total.
    /// @dev Assumes all offers share the same obligation id so that obligation shares are comparable.
    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    function bundleTakeShares(
        Midnight midnight,
        uint256 targetShares,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minBuyerAssets,
        uint256 maxBuyerAssets,
        uint256 minSellerAssets,
        uint256 maxSellerAssets,
        uint256 minObligationUnits,
        uint256 maxObligationUnits
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");

        uint256 totalFilledShares;
        uint256 totalBuyerAssets;
        uint256 totalSellerAssets;
        uint256 totalObligationUnits;
        for (uint256 i; i < takes.length && totalFilledShares < targetShares; i++) {
            try midnight.take(
                UtilsLib.min(targetShares - totalFilledShares, takes[i].obligationShares),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                takes[i].offer,
                takes[i].sig,
                takes[i].root,
                takes[i].proof
            ) returns (
                uint256 filledBuyerAssets,
                uint256 filledSellerAssets,
                uint256 filledObligationUnits,
                uint256 filledObligationShares
            ) {
                totalFilledShares += filledObligationShares;
                totalBuyerAssets += filledBuyerAssets;
                totalSellerAssets += filledSellerAssets;
                totalObligationUnits += filledObligationUnits;
            } catch {}
        }

        require(totalFilledShares == targetShares, "insufficient liquidity");
        require(totalBuyerAssets >= minBuyerAssets, "buyer assets below min");
        require(totalBuyerAssets <= maxBuyerAssets, "buyer assets above max");
        require(totalSellerAssets >= minSellerAssets, "seller assets below min");
        require(totalSellerAssets <= maxSellerAssets, "seller assets above max");
        require(totalObligationUnits >= minObligationUnits, "obligation units below min");
        require(totalObligationUnits <= maxObligationUnits, "obligation units above max");
    }

    /// @dev Same as bundleTakeShares but targets obligation units.
    /// @dev unitsToShares is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    function bundleTakeUnits(
        Midnight midnight,
        uint256 targetUnits,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minBuyerAssets,
        uint256 maxBuyerAssets,
        uint256 minSellerAssets,
        uint256 maxSellerAssets,
        uint256 minObligationShares,
        uint256 maxObligationShares
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        bytes32 id = midnight.toId(takes[0].offer.obligation);

        uint256 totalFilledUnits;
        uint256 totalBuyerAssets;
        uint256 totalSellerAssets;
        uint256 totalObligationShares;
        for (uint256 i; i < takes.length && totalFilledUnits < targetUnits; i++) {
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.unitsToShares(midnight, id, taker, takes[i].offer, targetUnits - totalFilledUnits),
                    takes[i].obligationShares
                ),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                takes[i].offer,
                takes[i].sig,
                takes[i].root,
                takes[i].proof
            ) returns (
                uint256 filledBuyerAssets,
                uint256 filledSellerAssets,
                uint256 filledObligationUnits,
                uint256 filledObligationShares
            ) {
                totalFilledUnits += filledObligationUnits;
                totalBuyerAssets += filledBuyerAssets;
                totalSellerAssets += filledSellerAssets;
                totalObligationShares += filledObligationShares;
            } catch {}
        }

        require(totalFilledUnits == targetUnits, "insufficient liquidity");
        require(totalBuyerAssets >= minBuyerAssets, "buyer assets below min");
        require(totalBuyerAssets <= maxBuyerAssets, "buyer assets above max");
        require(totalSellerAssets >= minSellerAssets, "seller assets below min");
        require(totalSellerAssets <= maxSellerAssets, "seller assets above max");
        require(totalObligationShares >= minObligationShares, "obligation shares below min");
        require(totalObligationShares <= maxObligationShares, "obligation shares above max");
    }

    /// @dev Same as bundleTakeShares but targets buyer assets.
    /// @dev Not usable if buyerPrice > WAD, because not all buyerAssets are reachable then.
    /// @dev buyerAssetsToShares is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    function bundleTakeBuyerAssets(
        Midnight midnight,
        uint256 targetBuyerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minObligationUnits,
        uint256 maxObligationUnits,
        uint256 minObligationShares,
        uint256 maxObligationShares
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        bytes32 id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.

        uint256 totalFilledBuyerAssets;
        uint256 totalObligationUnits;
        uint256 totalObligationShares;
        for (uint256 i; i < takes.length && totalFilledBuyerAssets < targetBuyerAssets; i++) {
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.buyerAssetsToShares(
                        midnight, id, takes[i].offer, targetBuyerAssets - totalFilledBuyerAssets
                    ),
                    takes[i].obligationShares
                ),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                takes[i].offer,
                takes[i].sig,
                takes[i].root,
                takes[i].proof
            ) returns (
                uint256 filledBuyerAssets, uint256, uint256 filledObligationUnits, uint256 filledObligationShares
            ) {
                totalFilledBuyerAssets += filledBuyerAssets;
                totalObligationUnits += filledObligationUnits;
                totalObligationShares += filledObligationShares;
            } catch {}
        }

        require(totalFilledBuyerAssets == targetBuyerAssets, "insufficient liquidity");
        require(totalObligationUnits >= minObligationUnits, "obligation units below min");
        require(totalObligationUnits <= maxObligationUnits, "obligation units above max");
        require(totalObligationShares >= minObligationShares, "obligation shares below min");
        require(totalObligationShares <= maxObligationShares, "obligation shares above max");
    }

    /// @dev Same as bundleTakeShares but targets seller assets.
    /// @dev sellerAssetsToShares is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    function bundleTakeSellerAssets(
        Midnight midnight,
        uint256 targetSellerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minObligationUnits,
        uint256 maxObligationUnits,
        uint256 minObligationShares,
        uint256 maxObligationShares
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        bytes32 id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.

        uint256 totalFilledSellerAssets;
        uint256 totalObligationUnits;
        uint256 totalObligationShares;
        for (uint256 i; i < takes.length && totalFilledSellerAssets < targetSellerAssets; i++) {
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.sellerAssetsToShares(
                        midnight, id, takes[i].offer, targetSellerAssets - totalFilledSellerAssets
                    ),
                    takes[i].obligationShares
                ),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                takes[i].offer,
                takes[i].sig,
                takes[i].root,
                takes[i].proof
            ) returns (
                uint256, uint256 filledSellerAssets, uint256 filledObligationUnits, uint256 filledObligationShares
            ) {
                totalFilledSellerAssets += filledSellerAssets;
                totalObligationUnits += filledObligationUnits;
                totalObligationShares += filledObligationShares;
            } catch {}
        }

        require(totalFilledSellerAssets == targetSellerAssets, "insufficient liquidity");
        require(totalObligationUnits >= minObligationUnits, "obligation units below min");
        require(totalObligationUnits <= maxObligationUnits, "obligation units above max");
        require(totalObligationShares >= minObligationShares, "obligation shares below min");
        require(totalObligationShares <= maxObligationShares, "obligation shares above max");
    }
}
