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

    /// @dev Iterates through orders, filling up to `targetUnits` obligation units total.
    /// @dev Assumes all offers share the same obligation id so that obligation shares are comparable.
    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev unitsToShares is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    function bundleTakeUnits(
        Midnight midnight,
        uint256 targetUnits,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");

        uint256 totalFilledUnits;
        for (uint256 i; i < takes.length && totalFilledUnits < targetUnits; i++) {
            Take calldata take = takes[i];
            try midnight.take(
                UtilsLib.min(targetUnits - totalFilledUnits, take.obligationUnits),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                take.offer,
                take.sig,
                take.root,
                take.proof
            ) returns (
                uint256, uint256, uint256 filledObligationUnits
            ) {
                totalFilledUnits += filledObligationUnits;
            } catch {}
        }

        require(totalFilledUnits == targetUnits, "insufficient liquidity");
    }

    /// @dev Same as bundleTakeUnits but targets buyer assets.
    /// @dev Not usable if buyerPrice > WAD, because not all buyerAssets are reachable then.
    /// @dev buyerAssetsToUnits is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    function bundleTakeBuyerAssets(
        Midnight midnight,
        uint256 targetBuyerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        bytes32 id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.

        uint256 totalFilledBuyerAssets;
        for (uint256 i; i < takes.length && totalFilledBuyerAssets < targetBuyerAssets; i++) {
            Take calldata take = takes[i];
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.buyerAssetsToUnits(
                        midnight, id, take.offer, targetBuyerAssets - totalFilledBuyerAssets
                    ),
                    take.obligationUnits
                ),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                take.offer,
                take.sig,
                take.root,
                take.proof
            ) returns (
                uint256 filledBuyerAssets, uint256, uint256
            ) {
                totalFilledBuyerAssets += filledBuyerAssets;
            } catch {}
        }

        require(totalFilledBuyerAssets == targetBuyerAssets, "insufficient liquidity");
    }

    /// @dev Same as bundleTakeUnits but targets seller assets.
    /// @dev sellerAssetsToUnits is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    function bundleTakeSellerAssets(
        Midnight midnight,
        uint256 targetSellerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        bytes32 id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.

        uint256 totalFilledSellerAssets;
        for (uint256 i; i < takes.length && totalFilledSellerAssets < targetSellerAssets; i++) {
            Take calldata take = takes[i];
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.sellerAssetsToUnits(
                        midnight, id, take.offer, targetSellerAssets - totalFilledSellerAssets
                    ),
                    take.obligationUnits
                ),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                take.offer,
                take.sig,
                take.root,
                take.proof
            ) returns (
                uint256, uint256 filledSellerAssets, uint256
            ) {
                totalFilledSellerAssets += filledSellerAssets;
            } catch {}
        }

        require(totalFilledSellerAssets == targetSellerAssets, "insufficient liquidity");
    }
}
