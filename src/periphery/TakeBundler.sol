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

    /// @dev Fills sell offers (taker is buyer) to hit the non-zero target dimension.
    /// @dev Exactly one of `targetUnits`, `targetBuyerAssets`, `targetSellerAssets` should be non-zero.
    /// @dev Assumes all offers are sell offers and share the same obligation id.
    /// @dev The taker must have authorized this bundler and msg.sender (if different) on Midnight.
    /// @dev Per-take reverts are swallowed: the offer is skipped.
    function buy(
        Midnight midnight,
        address taker,
        Take[] calldata takes,
        uint256 targetUnits,
        uint256 targetBuyerAssets,
        uint256 targetSellerAssets,
        uint256 minUnits,
        uint256 maxUnits,
        uint256 minBuyerAssets,
        uint256 maxBuyerAssets,
        uint256 minSellerAssets,
        uint256 maxSellerAssets
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        _fill(
            midnight,
            taker,
            address(0),
            takes,
            targetUnits,
            targetBuyerAssets,
            targetSellerAssets,
            minUnits,
            maxUnits,
            minBuyerAssets,
            maxBuyerAssets,
            minSellerAssets,
            maxSellerAssets
        );
    }

    /// @dev Fills buy offers (taker is seller) to hit the non-zero target dimension.
    /// @dev Exactly one of `targetUnits`, `targetBuyerAssets`, `targetSellerAssets` should be non-zero.
    /// @dev Assumes all offers are buy offers and share the same obligation id.
    /// @dev The taker must have authorized this bundler and msg.sender (if different) on Midnight.
    /// @dev Per-take reverts are swallowed: the offer is skipped.
    function sell(
        Midnight midnight,
        address taker,
        address receiver,
        Take[] calldata takes,
        uint256 targetUnits,
        uint256 targetBuyerAssets,
        uint256 targetSellerAssets,
        uint256 minUnits,
        uint256 maxUnits,
        uint256 minBuyerAssets,
        uint256 maxBuyerAssets,
        uint256 minSellerAssets,
        uint256 maxSellerAssets
    ) external {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        _fill(
            midnight,
            taker,
            receiver,
            takes,
            targetUnits,
            targetBuyerAssets,
            targetSellerAssets,
            minUnits,
            maxUnits,
            minBuyerAssets,
            maxBuyerAssets,
            minSellerAssets,
            maxSellerAssets
        );
    }

    /// @dev Iterates through `takes`, filling up to the non-zero target. Reverts if the target is not met exactly, or
    /// if any bound is violated.
    function _fill(
        Midnight midnight,
        address taker,
        address receiver,
        Take[] calldata takes,
        uint256 targetUnits,
        uint256 targetBuyerAssets,
        uint256 targetSellerAssets,
        uint256 minUnits,
        uint256 maxUnits,
        uint256 minBuyerAssets,
        uint256 maxBuyerAssets,
        uint256 minSellerAssets,
        uint256 maxSellerAssets
    ) internal {
        require(UtilsLib.atMostOneNonZero(targetUnits, targetBuyerAssets, targetSellerAssets), "multiple targets");

        bytes32 id;
        if (takes.length > 0 && (targetBuyerAssets > 0 || targetSellerAssets > 0)) {
            id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.
        }

        uint256 filledUnits;
        uint256 filledBuyerAssets;
        uint256 filledSellerAssets;
        for (uint256 i; i < takes.length; i++) {
            uint256 unitsToTake;
            if (targetUnits > 0) {
                if (filledUnits == targetUnits) break;
                unitsToTake = targetUnits - filledUnits;
            } else if (targetBuyerAssets > 0) {
                if (filledBuyerAssets == targetBuyerAssets) break;
                unitsToTake = TakeAmountsLib.buyerAssetsToUnits(
                    midnight, id, takes[i].offer, targetBuyerAssets - filledBuyerAssets
                );
            } else if (targetSellerAssets > 0) {
                if (filledSellerAssets == targetSellerAssets) break;
                unitsToTake = TakeAmountsLib.sellerAssetsToUnits(
                    midnight, id, takes[i].offer, targetSellerAssets - filledSellerAssets
                );
            } else {
                break;
            }

            try midnight.take(
                UtilsLib.min(unitsToTake, takes[i].units),
                taker,
                address(0),
                "",
                receiver,
                takes[i].offer,
                takes[i].sig,
                takes[i].root,
                takes[i].proof
            ) returns (
                uint256 fb, uint256 fs, uint256 fu
            ) {
                filledUnits += fu;
                filledBuyerAssets += fb;
                filledSellerAssets += fs;
            } catch {}
        }

        if (targetUnits > 0) require(filledUnits == targetUnits, "insufficient liquidity");
        else if (targetBuyerAssets > 0) require(filledBuyerAssets == targetBuyerAssets, "insufficient liquidity");
        else if (targetSellerAssets > 0) require(filledSellerAssets == targetSellerAssets, "insufficient liquidity");

        require(filledUnits >= minUnits, "units below min");
        require(filledUnits <= maxUnits, "units above max");
        require(filledBuyerAssets >= minBuyerAssets, "buyer assets below min");
        require(filledBuyerAssets <= maxBuyerAssets, "buyer assets above max");
        require(filledSellerAssets >= minSellerAssets, "seller assets below min");
        require(filledSellerAssets <= maxSellerAssets, "seller assets above max");
    }
}
