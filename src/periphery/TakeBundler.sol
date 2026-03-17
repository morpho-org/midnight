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
        uint256 obligationUnits;
        Offer offer;
        Signature sig;
        bytes32 root;
        bytes32[] proof;
    }

    /// @dev Iterates through orders, filling up to targetUnits obligation units total.
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
        uint256 minBuyerAssetsScaled,
        uint256 maxBuyerAssetsScaled,
        uint256 minSellerAssetsScaled,
        uint256 maxSellerAssetsScaled
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");

        uint256 totalFilledUnits;
        uint256 totalBuyerAssetsScaled;
        uint256 totalSellerAssetsScaled;
        for (uint256 i; i < takes.length && totalFilledUnits < targetUnits; i++) {
            try midnight.take(
                UtilsLib.min(targetUnits - totalFilledUnits, takes[i].obligationUnits),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                takes[i].offer,
                takes[i].sig,
                takes[i].root,
                takes[i].proof
            ) returns (
                uint256 filledBuyerAssets, uint256 filledSellerAssets, uint256 filledObligationUnits
            ) {
                totalFilledUnits += filledObligationUnits;
                totalBuyerAssetsScaled += filledBuyerAssets;
                totalSellerAssetsScaled += filledSellerAssets;
            } catch {}
        }

        require(totalFilledUnits == targetUnits, "insufficient liquidity");
        require(totalBuyerAssetsScaled >= minBuyerAssetsScaled, "buyer assets below min");
        require(totalBuyerAssetsScaled <= maxBuyerAssetsScaled, "buyer assets above max");
        require(totalSellerAssetsScaled >= minSellerAssetsScaled, "seller assets below min");
        require(totalSellerAssetsScaled <= maxSellerAssetsScaled, "seller assets above max");
    }

    /// @dev Same as bundleTakeUnits but targets buyer assets.
    /// @dev Not usable if buyerPrice > WAD, because not all buyerAssets are reachable then.
    /// @dev buyerAssetsToUnits is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    function bundleTakeBuyerAssets(
        Midnight midnight,
        uint256 targetBuyerAssetsScaled,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minObligationUnits,
        uint256 maxObligationUnits
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        bytes32 id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.

        uint256 totalFilledBuyerAssetsScaled;
        uint256 totalObligationUnits;
        for (uint256 i; i < takes.length && totalFilledBuyerAssetsScaled < targetBuyerAssetsScaled; i++) {
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.buyerAssetsToUnits(
                        midnight, id, takes[i].offer, targetBuyerAssetsScaled - totalFilledBuyerAssetsScaled
                    ),
                    takes[i].obligationUnits
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
                uint256 filledBuyerAssetsScaled, uint256, uint256 filledObligationUnits
            ) {
                totalFilledBuyerAssetsScaled += filledBuyerAssetsScaled;
                totalObligationUnits += filledObligationUnits;
            } catch {}
        }

        require(totalFilledBuyerAssetsScaled == targetBuyerAssetsScaled, "insufficient liquidity");
        require(totalObligationUnits >= minObligationUnits, "obligation units below min");
        require(totalObligationUnits <= maxObligationUnits, "obligation units above max");
    }

    /// @dev Same as bundleTakeUnits but targets seller assets.
    /// @dev sellerAssetsToUnits is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    function bundleTakeSellerAssets(
        Midnight midnight,
        uint256 targetSellerAssetsScaled,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minObligationUnits,
        uint256 maxObligationUnits
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        bytes32 id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.

        uint256 totalFilledSellerAssetsScaled;
        uint256 totalObligationUnits;
        for (uint256 i; i < takes.length && totalFilledSellerAssetsScaled < targetSellerAssetsScaled; i++) {
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.sellerAssetsToUnits(
                        midnight, id, takes[i].offer, targetSellerAssetsScaled - totalFilledSellerAssetsScaled
                    ),
                    takes[i].obligationUnits
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
                uint256, uint256 filledSellerAssets, uint256 filledObligationUnits
            ) {
                totalFilledSellerAssetsScaled += filledSellerAssets;
                totalObligationUnits += filledObligationUnits;
            } catch {}
        }

        require(totalFilledSellerAssetsScaled == targetSellerAssetsScaled, "insufficient liquidity");
        require(totalObligationUnits >= minObligationUnits, "obligation units below min");
        require(totalObligationUnits <= maxObligationUnits, "obligation units above max");
    }
}
