// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {Midnight} from "../Midnight.sol";
import {Offer} from "../interfaces/IMidnight.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";
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

    /// @dev Midnight's `take` fires maker-controlled callbacks after moving the loan token out of the bundler.
    /// Without this guard, a malicious callback could reenter any entry point with `target=0` to trigger its sweep,
    /// draining `bundleTakeUnits`'s residual balance (`maxBuyerAssets - totalBuyerAssets`) and shipping it to the
    /// attacker via `msg.sender`. The shared transient lock blocks cross-function reentry too.
    uint256 private transient _reentrancyLock;

    modifier nonReentrant() {
        require(_reentrancyLock == 0, "reentrancy");
        _reentrancyLock = 1;
        _;
        _reentrancyLock = 0;
    }

    /// @dev Iterates through orders, filling up to targetUnits units total.
    /// @dev Assumes offers are all buy or all sell and share the same obligation id.
    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev For sell offers the bundler pulls `maxBuyerAssets` from msg.sender, whom must have previously approved the
    /// bundler to spend their loan assets.
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
    ) external nonReentrant {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");

        address loanToken = takes[0].offer.obligation.loanToken;
        if (!takes[0].offer.buy) {
            SafeTransferLib.safeTransferFrom(loanToken, msg.sender, address(this), maxBuyerAssets);
            _approve(loanToken, address(midnight), maxBuyerAssets);
        }

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

        require(totalFilledUnits == targetUnits, "insufficient liquidity");
        require(totalBuyerAssets >= minBuyerAssets, "buyer assets below min");
        require(totalBuyerAssets <= maxBuyerAssets, "buyer assets above max");
        require(totalSellerAssets >= minSellerAssets, "seller assets below min");
        require(totalSellerAssets <= maxSellerAssets, "seller assets above max");

        _sweepAndRevoke(midnight, loanToken);
    }

    /// @dev Same as bundleTakeUnits but targets buyer assets.
    /// @dev Not usable if buyerPrice > WAD, because not all buyerAssets are reachable then.
    /// @dev buyerAssetsToUnits is evaluated before midnight.take, so reverts there (e.g. underflow when offerPrice <
    /// tradingFee) are not caught by the try/catch and will abort the bundle.
    /// @dev Requires a non-empty takes array.
    /// @dev For sell offers the bundler pulls `targetBuyerAssets` from msg.sender, whom must have previously approved
    /// the bundler to spend their loan assets.
    function bundleTakeBuyerAssets(
        Midnight midnight,
        uint256 targetBuyerAssets,
        address taker,
        address receiverIfTakerIsSeller,
        Take[] calldata takes,
        uint256 minUnits,
        uint256 maxUnits
    ) external nonReentrant {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        bytes32 id = midnight.touchObligation(takes[0].offer.obligation); // to have the correct trading fees.

        address loanToken = takes[0].offer.obligation.loanToken;
        if (!takes[0].offer.buy) {
            SafeTransferLib.safeTransferFrom(loanToken, msg.sender, address(this), targetBuyerAssets);
            _approve(loanToken, address(midnight), targetBuyerAssets);
        }

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

        require(totalFilledBuyerAssets == targetBuyerAssets, "insufficient liquidity");
        require(totalUnits >= minUnits, "units below min");
        require(totalUnits <= maxUnits, "units above max");

        _sweepAndRevoke(midnight, loanToken);
    }

    /// @dev Same as bundleTakeUnits but targets seller assets.
    /// @dev Only supports buy offers because for sell offers the bundler does not know how many buyer assets it
    /// needs to pull from msg.sender.
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
    ) external nonReentrant {
        require(taker == msg.sender || midnight.isAuthorized(taker, msg.sender), "unauthorized");
        require(takes[0].offer.buy, "sell offers unsupported");
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

        require(totalFilledSellerAssets == targetSellerAssets, "insufficient liquidity");
        require(totalUnits >= minUnits, "units below min");
        require(totalUnits <= maxUnits, "units above max");
    }

    /// @dev Revokes Midnight's allowance and returns any residual loan-token balance to `msg.sender`.
    function _sweepAndRevoke(Midnight midnight, address loanToken) private {
        _approve(loanToken, address(midnight), 0);
        uint256 residual = IERC20(loanToken).balanceOf(address(this));
        if (residual > 0) SafeTransferLib.safeTransfer(loanToken, msg.sender, residual);
    }

    /// @dev Simplified version of OZ safeApprove.
    function _approve(address token, address spender, uint256 value) private {
        (bool success, bytes memory returndata) = token.call(abi.encodeCall(IERC20.approve, (spender, value)));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "approve failed");
    }
}
