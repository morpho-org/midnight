// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight, Obligation} from "../interfaces/IMidnight.sol";
import {IBuyCallback} from "../interfaces/ICallbacks.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ITakeBundler, Take} from "./interfaces/ITakeBundler.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";

contract TakeBundler is ITakeBundler, IBuyCallback {
    using UtilsLib for uint256;

    /// @dev Transient caller address set before each take and consumed by onBuy.
    address public transient _caller;

    /// @dev Assumes offers are all share the same obligation id.
    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    function buyUnitsTarget(
        address midnight,
        uint256 targetUnits,
        address taker,
        Take[] calldata takes,
        uint256 minBuyerAssets,
        uint256 maxBuyerAssets
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());

        uint256 totalFilledUnits;
        uint256 totalBuyerAssets;
        for (uint256 i; i < takes.length && totalFilledUnits < targetUnits; i++) {
            _caller = msg.sender;
            try IMidnight(midnight)
                .take(
                    UtilsLib.min(targetUnits - totalFilledUnits, takes[i].units),
                    taker,
                    address(this),
                    "",
                    address(0),
                    takes[i].offer,
                    takes[i].ratifierData,
                    takes[i].root,
                    takes[i].proof
                ) returns (
                uint256 filledBuyerAssets, uint256, uint256 filledUnits
            ) {
                totalFilledUnits += filledUnits;
                totalBuyerAssets += filledBuyerAssets;
            } catch {}
        }

        require(totalFilledUnits == targetUnits, InsufficientLiquidity());
        require(totalBuyerAssets >= minBuyerAssets, BuyerAssetsBelowMin());
        require(totalBuyerAssets <= maxBuyerAssets, BuyerAssetsAboveMax());
    }

    /// @dev See sellUnitsTarget.
    function sellUnitsTarget(
        address midnight,
        uint256 targetUnits,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minSellerAssets,
        uint256 maxSellerAssets
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());

        uint256 totalFilledUnits;
        uint256 totalSellerAssets;
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
                uint256, uint256 filledSellerAssets, uint256 filledUnits
            ) {
                totalFilledUnits += filledUnits;
                totalSellerAssets += filledSellerAssets;
            } catch {}
        }

        require(totalFilledUnits == targetUnits, InsufficientLiquidity());
        require(totalSellerAssets >= minSellerAssets, SellerAssetsBelowMin());
        require(totalSellerAssets <= maxSellerAssets, SellerAssetsAboveMax());
    }

    /// @dev See buyBuyerAssetsTarget.
    function buyBuyerAssetsTarget(
        address midnight,
        uint256 targetBuyerAssets,
        address taker,
        Take[] calldata takes,
        uint256 minUnits,
        uint256 maxUnits
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        // touchObligation to have the correct trading fees.
        bytes32 id = IMidnight(midnight).touchObligation(takes[0].offer.obligation);

        uint256 totalFilledBuyerAssets;
        uint256 totalUnits;
        for (uint256 i; i < takes.length && totalFilledBuyerAssets < targetBuyerAssets; i++) {
            _caller = msg.sender;
            try IMidnight(midnight)
                .take(
                    UtilsLib.min(
                        TakeAmountsLib.buyerAssetsToUnits(
                            midnight, id, takes[i].offer, targetBuyerAssets - totalFilledBuyerAssets
                        ),
                        takes[i].units
                    ),
                    taker,
                    address(this),
                    "",
                    address(0),
                    takes[i].offer,
                    takes[i].ratifierData,
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

    /// @dev See sellSellerAssetsTarget.
    function sellSellerAssetsTarget(
        address midnight,
        uint256 targetSellerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minUnits,
        uint256 maxUnits
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        // touchObligation to have the correct trading fees.
        bytes32 id = IMidnight(midnight).touchObligation(takes[0].offer.obligation);

        uint256 totalFilledSellerAssets;
        uint256 totalUnits;
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

    /// @dev Pulls buyerAssets from the caller (stored in transient storage) and approves the Midnight contract to spend
    /// them. Only callable during an active buy function execution (_caller is set before each take and consumed here).
    function onBuy(bytes32, Obligation memory obligation, address, uint256 buyerAssets, uint256, bytes memory)
        external
        returns (bytes32)
    {
        address payer = _caller;
        require(payer != address(0), Unauthorized());
        _caller = address(0);
        SafeTransferLib.safeTransferFrom(obligation.loanToken, payer, address(this), buyerAssets);
        IERC20(obligation.loanToken).approve(msg.sender, buyerAssets);
        return CALLBACK_SUCCESS;
    }
}
