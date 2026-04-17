// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight} from "../interfaces/IMidnight.sol";
import {ITakeBundler, Take} from "./interfaces/ITakeBundler.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";

contract TakeBundler is ITakeBundler {
    using UtilsLib for uint256;

    /// @dev Iterates through offers, filling up to targetUnits units total.
    /// @dev Assumes offers are all buy or all sell and share the same obligation id.
    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    function buyUnitsTarget(
        address midnight,
        uint256 targetUnits,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());

        uint256 totalFilledUnits;
        for (uint256 i; i < takes.length && totalFilledUnits < targetUnits; i++) {
            try IMidnight(midnight)
                .take(
                    UtilsLib.min(targetUnits - totalFilledUnits, takes[i].units),
                    taker,
                    address(0),
                    "",
                    receiverIfTakerIsSeller,
                    takes[i].offer,
                    takes[i].ratifierData,
                    takes[i].root,
                    takes[i].proof
                ) returns (
                uint256, uint256, uint256 filledUnits
            ) {
                totalFilledUnits += filledUnits;
            } catch {}
        }

        require(totalFilledUnits == targetUnits, InsufficientLiquidity());
    }

    /// @dev Same as buyUnitsTarget but targets buyer assets.
    /// @dev Not usable if buyerPrice > WAD, because not all buyerAssets are reachable then.
    /// @dev buyerAssetsToUnits is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    /// @dev Requires a non-empty takes array.
    function buyAssetsTarget(
        address midnight,
        uint256 targetBuyerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        bytes32 id = IMidnight(midnight).touchObligation(takes[0].offer.obligation);

        uint256 totalFilledBuyerAssets;
        for (uint256 i; i < takes.length && totalFilledBuyerAssets < targetBuyerAssets; i++) {
            try IMidnight(midnight)
                .take(
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
                    takes[i].ratifierData,
                    takes[i].root,
                    takes[i].proof
                ) returns (
                uint256 filledBuyerAssets, uint256, uint256
            ) {
                totalFilledBuyerAssets += filledBuyerAssets;
            } catch {}
        }

        require(totalFilledBuyerAssets == targetBuyerAssets, InsufficientLiquidity());
    }

    /// @dev Same as buyUnitsTarget but for selling.
    function sellUnitsTarget(
        address midnight,
        uint256 targetUnits,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());

        uint256 totalFilledUnits;
        for (uint256 i; i < takes.length && totalFilledUnits < targetUnits; i++) {
            try IMidnight(midnight)
                .take(
                    UtilsLib.min(targetUnits - totalFilledUnits, takes[i].units),
                    taker,
                    address(0),
                    "",
                    receiverIfTakerIsSeller,
                    takes[i].offer,
                    takes[i].ratifierData,
                    takes[i].root,
                    takes[i].proof
                ) returns (
                uint256, uint256, uint256 filledUnits
            ) {
                totalFilledUnits += filledUnits;
            } catch {}
        }

        require(totalFilledUnits == targetUnits, InsufficientLiquidity());
    }

    /// @dev Same as sellUnitsTarget but targets seller assets.
    /// @dev sellerAssetsToUnits is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    /// @dev Requires a non-empty takes array.
    function sellAssetsTarget(
        address midnight,
        uint256 targetSellerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        bytes32 id = IMidnight(midnight).touchObligation(takes[0].offer.obligation);

        uint256 totalFilledSellerAssets;
        for (uint256 i; i < takes.length && totalFilledSellerAssets < targetSellerAssets; i++) {
            try IMidnight(midnight)
                .take(
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
                    takes[i].ratifierData,
                    takes[i].root,
                    takes[i].proof
                ) returns (
                uint256, uint256 filledSellerAssets, uint256
            ) {
                totalFilledSellerAssets += filledSellerAssets;
            } catch {}
        }

        require(totalFilledSellerAssets == targetSellerAssets, InsufficientLiquidity());
    }
}
