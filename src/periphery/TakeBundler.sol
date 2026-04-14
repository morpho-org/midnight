// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {Midnight} from "../Midnight.sol";
import {ITakeBundler, Take} from "./interfaces/ITakeBundler.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";

contract TakeBundler is ITakeBundler {
    using UtilsLib for uint256;

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
        uint256 minBuyerAssets,
        uint256 maxBuyerAssets,
        uint256 minSellerAssets,
        uint256 maxSellerAssets
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), Unauthorized());

        uint256 totalFilledUnits;
        uint256 totalBuyerAssets;
        uint256 totalSellerAssets;
        for (uint256 i; i < takes.length && totalFilledUnits < targetUnits; i++) {
            try midnight.take(
                UtilsLib.min(targetUnits - totalFilledUnits, takes[i].units),
                taker,
                address(0),
                "",
                receiverIfTakerIsSeller,
                takes[i].offer,
                takes[i].sig,
                takes[i].root,
                takes[i].proof
            ) returns (
                uint256 filledBuyerAssets, uint256 filledSellerAssets, uint256 filledUnits
            ) {
                totalFilledUnits += filledUnits;
                totalBuyerAssets += filledBuyerAssets;
                totalSellerAssets += filledSellerAssets;
            } catch {}
        }

        require(totalFilledUnits == targetUnits, InsufficientLiquidity());
        require(totalBuyerAssets >= minBuyerAssets, BuyerAssetsBelowMin());
        require(totalBuyerAssets <= maxBuyerAssets, BuyerAssetsAboveMax());
        require(totalSellerAssets >= minSellerAssets, SellerAssetsBelowMin());
        require(totalSellerAssets <= maxSellerAssets, SellerAssetsAboveMax());
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
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), Unauthorized());
        bytes32 id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.

        uint256 totalFilledBuyerAssets;
        uint256 totalUnits;
        for (uint256 i; i < takes.length && totalFilledBuyerAssets < targetBuyerAssets; i++) {
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.buyerAssetsToUnits(
                        midnight, id, takes[i].offer, targetBuyerAssets - totalFilledBuyerAssets
                    ),
                    takes[i].units
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
                uint256 filledBuyerAssets, uint256, uint256 filledUnits
            ) {
                totalFilledBuyerAssets += filledBuyerAssets;
                totalUnits += filledUnits;
            } catch {}
        }

        require(totalFilledBuyerAssets == targetBuyerAssets, InsufficientLiquidity());
        require(totalUnits >= minUnits, UnitsBelowMin());
        require(totalUnits <= maxUnits, UnitsAboveMax());
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
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), Unauthorized());
        bytes32 id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.

        uint256 totalFilledSellerAssets;
        uint256 totalUnits;
        for (uint256 i; i < takes.length && totalFilledSellerAssets < targetSellerAssets; i++) {
            try midnight.take(
                UtilsLib.min(
                    TakeAmountsLib.sellerAssetsToUnits(
                        midnight, id, takes[i].offer, targetSellerAssets - totalFilledSellerAssets
                    ),
                    takes[i].units
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
                uint256, uint256 filledSellerAssets, uint256 filledUnits
            ) {
                totalFilledSellerAssets += filledSellerAssets;
                totalUnits += filledUnits;
            } catch {}
        }

        require(totalFilledSellerAssets == targetSellerAssets, InsufficientLiquidity());
        require(totalUnits >= minUnits, UnitsBelowMin());
        require(totalUnits <= maxUnits, UnitsAboveMax());
    }
}
