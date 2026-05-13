// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight, Obligation} from "../interfaces/IMidnight.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {
    IMidnightBundles,
    Take,
    CollateralWithdrawal,
    CollateralSupply,
    TokenPermit,
    PermitKind
} from "./interfaces/IMidnightBundles.sol";
import {IERC20Permit} from "./interfaces/IERC20Permit.sol";
import {IPermit2} from "./interfaces/IPermit2.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";

contract MidnightBundles is IMidnightBundles {
    using UtilsLib for uint256;

    /// @dev Canonical Permit2 deployment.
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev This function should only be called with the same obligation for all takes.
    /// @dev The collateral transfers always use the first offer's obligation.
    /// @dev Skips every reason why take can revert (including ones that are not asynchrony related).
    /// @dev Reverts if TakeAmountsLib reverts.
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev This function pulls maxBuyerAssets from the msg.sender and transfers back the remaining tokens at the end.
    /// @dev The msg.sender will pay at most maxBuyerAssets.
    /// @dev Total loan-token cost is filledBuyerAssets + filledBuyerAssets * pct / (WAD - pct).
    function buyWithUnitsTargetAndWithdrawCollateral(
        address midnight,
        uint256 targetUnits,
        uint256 maxBuyerAssets,
        address taker,
        TokenPermit memory loanTokenPermit,
        Take[] memory takes,
        CollateralWithdrawal[] memory collateralWithdrawals,
        address collateralReceiver,
        uint256 referralFeePct,
        address referralFeeRecipient
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        require(referralFeePct < WAD, PctExceeded());
        address loanToken = takes[0].offer.obligation.loanToken;
        bytes32 id = IMidnight(midnight).toId(takes[0].offer.obligation);

        _forceApproveMax(loanToken, midnight);
        _pullToken(loanToken, msg.sender, maxBuyerAssets, loanTokenPermit);

        uint256 filledUnits;
        uint256 filledBuyerAssets;
        for (uint256 i; i < takes.length && filledUnits < targetUnits; i++) {
            require(!takes[i].offer.buy, InconsistentSide());
            require(IMidnight(midnight).toId(takes[i].offer.obligation) == id, InconsistentObligation());
            uint256 unitsToTake = UtilsLib.min(targetUnits - filledUnits, takes[i].units);
            try IMidnight(midnight)
                .take(unitsToTake, taker, address(0), "", address(0), takes[i].offer, takes[i].ratifierData) returns (
                uint256 resBuyerAssets, uint256
            ) {
                filledUnits += unitsToTake;
                filledBuyerAssets += resBuyerAssets;
            } catch {}
        }

        require(filledUnits == targetUnits, OutOfOffers());

        Obligation memory obligation = takes[0].offer.obligation;
        for (uint256 i; i < collateralWithdrawals.length; i++) {
            IMidnight(midnight)
                .withdrawCollateral(
                    obligation,
                    collateralWithdrawals[i].collateralIndex,
                    collateralWithdrawals[i].assets,
                    taker,
                    collateralReceiver
                );
        }

        uint256 referralFeeAssets = filledBuyerAssets.mulDivDown(referralFeePct, WAD - referralFeePct);
        if (referralFeeAssets > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFeeAssets);
        SafeTransferLib.safeTransfer(loanToken, msg.sender, maxBuyerAssets - filledBuyerAssets - referralFeeAssets);
    }

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev This function should only be called with the same obligation for all takes.
    /// @dev The collateral transfers always use the first offer's obligation.
    /// @dev Skips every reason why take can revert (including ones that are not asynchrony related).
    /// @dev Reverts if TakeAmountsLib reverts.
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev The msg.sender should have approved the bundler to transfer enough collateral.
    /// @dev The receiver will receive at least minSellerAssets.
    /// @dev Total receipt is filledSellerAssets - filledSellerAssets * pct / WAD.
    function supplyCollateralAndSellWithUnitsTarget(
        address midnight,
        uint256 targetUnits,
        uint256 minSellerAssets,
        address taker,
        address receiver,
        CollateralSupply[] memory collateralSupplies,
        Take[] memory takes,
        uint256 referralFeePct,
        address referralFeeRecipient
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        require(referralFeePct < WAD, PctExceeded());
        address loanToken = takes[0].offer.obligation.loanToken;
        bytes32 id = IMidnight(midnight).toId(takes[0].offer.obligation);

        Obligation memory obligation = takes[0].offer.obligation;
        for (uint256 i; i < collateralSupplies.length; i++) {
            address token = obligation.collateralParams[collateralSupplies[i].collateralIndex].token;
            _pullToken(token, msg.sender, collateralSupplies[i].assets, collateralSupplies[i].permit);
            _forceApproveMax(token, midnight);
            IMidnight(midnight)
                .supplyCollateral(
                    obligation, collateralSupplies[i].collateralIndex, collateralSupplies[i].assets, taker
                );
        }

        uint256 filledUnits;
        uint256 filledSellerAssets;
        for (uint256 i; i < takes.length && filledUnits < targetUnits; i++) {
            require(takes[i].offer.buy, InconsistentSide());
            require(IMidnight(midnight).toId(takes[i].offer.obligation) == id, InconsistentObligation());
            uint256 unitsToTake = UtilsLib.min(targetUnits - filledUnits, takes[i].units);
            try IMidnight(midnight)
                .take(
                    unitsToTake, taker, address(0), "", address(this), takes[i].offer, takes[i].ratifierData
                ) returns (
                uint256, uint256 resSellerAssets
            ) {
                filledUnits += unitsToTake;
                filledSellerAssets += resSellerAssets;
            } catch {}
        }

        require(filledUnits == targetUnits, OutOfOffers());

        uint256 referralFeeAssets = filledSellerAssets.mulDivDown(referralFeePct, WAD);
        require(filledSellerAssets - referralFeeAssets >= minSellerAssets, SellerAssetsTooLow());
        if (referralFeeAssets > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFeeAssets);
        SafeTransferLib.safeTransfer(loanToken, receiver, filledSellerAssets - referralFeeAssets);
    }

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev This function should only be called with the same obligation for all takes.
    /// @dev The collateral transfers always use the first offer's obligation.
    /// @dev Skips every reason why take can revert (including ones that are not asynchrony related).
    /// @dev Reverts if TakeAmountsLib reverts.
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev Total cost is targetBuyerAssets.
    /// @dev The taker will gain at least minUnits.
    /// @dev The referral fee changes the amount that must be filled, which can change the average taking price.
    function buyWithAssetsTargetAndWithdrawCollateral(
        address midnight,
        uint256 targetBuyerAssets,
        uint256 minUnits,
        address taker,
        TokenPermit memory loanTokenPermit,
        Take[] memory takes,
        CollateralWithdrawal[] memory collateralWithdrawals,
        address collateralReceiver,
        uint256 referralFeePct,
        address referralFeeRecipient
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        require(referralFeePct < WAD, PctExceeded());

        // touchObligation to have the correct trading fees.
        bytes32 id = IMidnight(midnight).touchObligation(takes[0].offer.obligation);
        _forceApproveMax(takes[0].offer.obligation.loanToken, midnight);
        _pullToken(takes[0].offer.obligation.loanToken, msg.sender, targetBuyerAssets, loanTokenPermit);

        uint256 referralFeeAssets = targetBuyerAssets.mulDivDown(referralFeePct, WAD);
        uint256 targetFilledBuyerAssets = targetBuyerAssets - referralFeeAssets;

        uint256 filledBuyerAssets;
        uint256 filledUnits;
        for (uint256 i; i < takes.length && filledBuyerAssets < targetFilledBuyerAssets; i++) {
            require(!takes[i].offer.buy, InconsistentSide());
            require(IMidnight(midnight).toId(takes[i].offer.obligation) == id, InconsistentObligation());
            uint256 unitsToTake = UtilsLib.min(
                TakeAmountsLib.buyerAssetsToUnits(
                    midnight, id, takes[i].offer, targetFilledBuyerAssets - filledBuyerAssets
                ),
                takes[i].units
            );
            try IMidnight(midnight)
                .take(unitsToTake, taker, address(0), "", address(0), takes[i].offer, takes[i].ratifierData) returns (
                uint256 resBuyerAssets, uint256
            ) {
                filledBuyerAssets += resBuyerAssets;
                filledUnits += unitsToTake;
            } catch {}
        }

        require(filledBuyerAssets == targetFilledBuyerAssets, OutOfOffers());
        require(filledUnits >= minUnits, UnitsTooLow());

        Obligation memory obligation = takes[0].offer.obligation;
        for (uint256 i; i < collateralWithdrawals.length; i++) {
            IMidnight(midnight)
                .withdrawCollateral(
                    obligation,
                    collateralWithdrawals[i].collateralIndex,
                    collateralWithdrawals[i].assets,
                    taker,
                    collateralReceiver
                );
        }

        address loanToken = takes[0].offer.obligation.loanToken;
        if (referralFeeAssets > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFeeAssets);
    }

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev This function should only be called with the same obligation for all takes.
    /// @dev The collateral transfers always use the first offer's obligation.
    /// @dev Skips every reason why take can revert (including ones that are not asynchrony related).
    /// @dev Reverts if TakeAmountsLib reverts.
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev The msg.sender should have approved the bundler to transfer enough collateral.
    /// @dev Total receipt is targetSellerAssets.
    /// @dev The taker will lose at most maxUnits.
    /// @dev The referral fee changes the amount that must be filled, which can change the average taking price.
    function supplyCollateralAndSellWithAssetsTarget(
        address midnight,
        uint256 targetSellerAssets,
        uint256 maxUnits,
        address taker,
        address receiver,
        CollateralSupply[] memory collateralSupplies,
        Take[] memory takes,
        uint256 referralFeePct,
        address referralFeeRecipient
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        require(referralFeePct < WAD, PctExceeded());
        address loanToken = takes[0].offer.obligation.loanToken;
        // touchObligation to have the correct trading fees.
        bytes32 id = IMidnight(midnight).touchObligation(takes[0].offer.obligation);

        Obligation memory obligation = takes[0].offer.obligation;
        for (uint256 i; i < collateralSupplies.length; i++) {
            address token = obligation.collateralParams[collateralSupplies[i].collateralIndex].token;
            _pullToken(token, msg.sender, collateralSupplies[i].assets, collateralSupplies[i].permit);
            _forceApproveMax(token, midnight);
            IMidnight(midnight)
                .supplyCollateral(
                    obligation, collateralSupplies[i].collateralIndex, collateralSupplies[i].assets, taker
                );
        }

        uint256 referralFeeAssets = targetSellerAssets.mulDivDown(referralFeePct, WAD - referralFeePct);
        uint256 targetFilledSellerAssets = targetSellerAssets + referralFeeAssets;

        uint256 filledSellerAssets;
        uint256 filledUnits;
        for (uint256 i; i < takes.length && filledSellerAssets < targetFilledSellerAssets; i++) {
            require(takes[i].offer.buy, InconsistentSide());
            require(IMidnight(midnight).toId(takes[i].offer.obligation) == id, InconsistentObligation());
            uint256 unitsToTake = UtilsLib.min(
                TakeAmountsLib.sellerAssetsToUnits(
                    midnight, id, takes[i].offer, targetFilledSellerAssets - filledSellerAssets
                ),
                takes[i].units
            );
            try IMidnight(midnight)
                .take(
                    unitsToTake, taker, address(0), "", address(this), takes[i].offer, takes[i].ratifierData
                ) returns (
                uint256, uint256 resSellerAssets
            ) {
                filledSellerAssets += resSellerAssets;
                filledUnits += unitsToTake;
            } catch {}
        }

        require(filledSellerAssets == targetFilledSellerAssets, OutOfOffers());
        require(filledUnits <= maxUnits, UnitsTooHigh());

        if (referralFeeAssets > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFeeAssets);
        SafeTransferLib.safeTransfer(loanToken, receiver, targetSellerAssets);
    }

    /// @dev The onBehalf must have authorized this contract and the msg.sender (if different from onBehalf) on
    /// Midnight.
    /// @dev The msg.sender must have approved the contract to transfer assets of the obligation's loan token.
    /// @dev Fee = assets * pct / WAD; units repaid = assets - fee.
    /// @dev To fully repay a debt D, pass assets = floor(D * WAD / (WAD - pct)).
    function repayAndWithdrawCollateral(
        address midnight,
        Obligation memory obligation,
        uint256 assets,
        address onBehalf,
        TokenPermit memory loanTokenPermit,
        CollateralWithdrawal[] memory collateralWithdrawals,
        address collateralReceiver,
        uint256 referralFeePct,
        address referralFeeRecipient
    ) external {
        require(onBehalf == msg.sender || IMidnight(midnight).isAuthorized(onBehalf, msg.sender), Unauthorized());
        require(referralFeePct < WAD, PctExceeded());

        address loanToken = obligation.loanToken;
        uint256 referralFeeAssets = assets.mulDivDown(referralFeePct, WAD);
        uint256 units = assets - referralFeeAssets;
        _pullToken(loanToken, msg.sender, assets, loanTokenPermit);
        _forceApproveMax(loanToken, midnight);

        IMidnight(midnight).repay(obligation, units, onBehalf, address(0), "");

        for (uint256 i; i < collateralWithdrawals.length; i++) {
            IMidnight(midnight)
                .withdrawCollateral(
                    obligation,
                    collateralWithdrawals[i].collateralIndex,
                    collateralWithdrawals[i].assets,
                    onBehalf,
                    collateralReceiver
                );
        }

        if (referralFeeAssets > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFeeAssets);
    }

    function _safeApprove(address token, address spender, uint256 value) internal {
        (bool success, bytes memory returndata) = token.call(abi.encodeCall(IERC20.approve, (spender, value)));
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returndata, 0x20), mload(returndata))
            }
        }
        require(returndata.length == 0 || abi.decode(returndata, (bool)));
    }

    /// @dev Skips the approval entirely when the current allowance is already 2^95 - 1.
    /// @dev Resets to 0 before re-approving to support USDT like tokens.
    function _forceApproveMax(address token, address spender) internal {
        if (IERC20(token).allowance(address(this), spender) >= type(uint96).max / 2) return;
        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, type(uint256).max);
    }

    /// @dev Pulls `amount` of `token` from `from` to this bundler, optionally using ERC2612 or Permit2.
    function _pullToken(address token, address from, uint256 amount, TokenPermit memory permit) internal {
        if (permit.kind == PermitKind.ERC2612) {
            (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
                abi.decode(permit.data, (uint256, uint8, bytes32, bytes32));
            // Tolerate revert: a third party may have already consumed the permit.
            try IERC20Permit(token).permit(from, address(this), amount, deadline, v, r, s) {} catch {}
            SafeTransferLib.safeTransferFrom(token, from, address(this), amount);
        } else if (permit.kind == PermitKind.Permit2) {
            (uint256 nonce, uint256 deadline, bytes memory signature) =
                abi.decode(permit.data, (uint256, uint256, bytes));
            IPermit2(PERMIT2)
                .permitTransferFrom(
                    IPermit2.PermitTransferFrom(IPermit2.TokenPermissions(token, amount), nonce, deadline),
                    IPermit2.SignatureTransferDetails(address(this), amount),
                    from,
                    signature
                );
        } else {
            SafeTransferLib.safeTransferFrom(token, from, address(this), amount);
        }
    }
}
