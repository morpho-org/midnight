// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight, Obligation} from "../interfaces/IMidnight.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ITakeBundler, Take, CollateralTransfer} from "./interfaces/ITakeBundler.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";

contract TakeBundler is ITakeBundler {
    using UtilsLib for uint256;

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev Skips every reason why take can revert (including ones that are not asynchrony related).
    /// @dev Reverts if TakeAmountsLib reverts.
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev This function pulls maxBuyerAssets from the msg.sender and transfers back the remaining tokens at the end.
    /// @dev Total loan-token cost is filledBuyerAssets + filledBuyerAssets * pct / (WAD - pct).
    function buyUnitsTarget(
        address midnight,
        uint256 targetUnits,
        uint256 maxBuyerAssets,
        address taker,
        Take[] calldata takes,
        CollateralTransfer[] calldata collateralWithdrawals,
        address collateralReceiver,
        uint256 referralFeePct,
        address referralFeeRecipient
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        require(referralFeePct < WAD, PctExceeded());
        address loanToken = takes[0].offer.obligation.loanToken;
        bytes32 id = IMidnight(midnight).toId(takes[0].offer.obligation);

        _forceApproveMax(loanToken, midnight);
        SafeTransferLib.safeTransferFrom(loanToken, msg.sender, address(this), maxBuyerAssets);

        uint256 filledUnits;
        uint256 filledBuyerAssets;
        for (uint256 i; i < takes.length && filledUnits < targetUnits; i++) {
            require(!takes[i].offer.buy, InconsistentSide());
            require(IMidnight(midnight).toId(takes[i].offer.obligation) == id, InconsistentObligation());
            try IMidnight(midnight)
                .take(
                    UtilsLib.min(targetUnits - filledUnits, takes[i].units),
                    taker,
                    address(0),
                    "",
                    address(0),
                    takes[i].offer,
                    takes[i].ratifierData,
                    takes[i].root,
                    takes[i].proof
                ) returns (
                uint256 resBuyerAssets, uint256, uint256 resUnits
            ) {
                filledUnits += resUnits;
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
    /// @dev Skips every reason why take can revert (including ones that are not asynchrony related).
    /// @dev Reverts if TakeAmountsLib reverts.
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev The msg.sender should have approved the bundler to transfer enough collateral.
    /// @dev Total receipt is filledSellerAssets - filledSellerAssets * pct / WAD.
    function sellUnitsTarget(
        address midnight,
        uint256 targetUnits,
        address taker,
        address receiver,
        Take[] calldata takes,
        CollateralTransfer[] calldata collateralSupplies,
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
            SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), collateralSupplies[i].assets);
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
            try IMidnight(midnight)
                .take(
                    UtilsLib.min(targetUnits - filledUnits, takes[i].units),
                    taker,
                    address(0),
                    "",
                    address(this),
                    takes[i].offer,
                    takes[i].ratifierData,
                    takes[i].root,
                    takes[i].proof
                ) returns (
                uint256, uint256 resSellerAssets, uint256 resUnits
            ) {
                filledUnits += resUnits;
                filledSellerAssets += resSellerAssets;
            } catch {}
        }

        require(filledUnits == targetUnits, OutOfOffers());

        uint256 referralFeeAssets = filledSellerAssets.mulDivDown(referralFeePct, WAD);
        if (referralFeeAssets > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFeeAssets);
        SafeTransferLib.safeTransfer(loanToken, receiver, filledSellerAssets - referralFeeAssets);
    }

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev Skips every reason why take can revert (including ones that are not asynchrony related).
    /// @dev Reverts if TakeAmountsLib reverts.
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev Total cost is targetBuyerAssets.
    /// @dev The referral fee changes the amount that must be filled, which can change the average taking price.
    function buyBuyerAssetsTarget(
        address midnight,
        uint256 targetBuyerAssets,
        address taker,
        Take[] calldata takes,
        CollateralTransfer[] calldata collateralWithdrawals,
        address collateralReceiver,
        uint256 referralFeePct,
        address referralFeeRecipient
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        require(referralFeePct < WAD, PctExceeded());

        address loanToken = takes[0].offer.obligation.loanToken;
        // touchObligation to have the correct trading fees.
        bytes32 id = IMidnight(midnight).touchObligation(takes[0].offer.obligation);
        _forceApproveMax(loanToken, midnight);
        SafeTransferLib.safeTransferFrom(loanToken, msg.sender, address(this), targetBuyerAssets);

        uint256 referralFeeAssets = targetBuyerAssets.mulDivDown(referralFeePct, WAD);
        uint256 targetFilledBuyerAssets = targetBuyerAssets - referralFeeAssets;

        uint256 filledBuyerAssets;
        for (uint256 i; i < takes.length && filledBuyerAssets < targetFilledBuyerAssets; i++) {
            require(!takes[i].offer.buy, InconsistentSide());
            require(IMidnight(midnight).toId(takes[i].offer.obligation) == id, InconsistentObligation());
            try IMidnight(midnight)
                .take(
                    UtilsLib.min(
                        TakeAmountsLib.buyerAssetsToUnits(
                            midnight, id, takes[i].offer, targetFilledBuyerAssets - filledBuyerAssets
                        ),
                        takes[i].units
                    ),
                    taker,
                    address(0),
                    "",
                    address(0),
                    takes[i].offer,
                    takes[i].ratifierData,
                    takes[i].root,
                    takes[i].proof
                ) returns (
                uint256 resBuyerAssets, uint256, uint256
            ) {
                filledBuyerAssets += resBuyerAssets;
            } catch {}
        }

        require(filledBuyerAssets == targetFilledBuyerAssets, OutOfOffers());

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

        if (referralFeeAssets > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFeeAssets);
    }

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev Skips every reason why take can revert (including ones that are not asynchrony related).
    /// @dev Reverts if TakeAmountsLib reverts.
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev The msg.sender should have approved the bundler to transfer enough collateral.
    /// @dev Total receipt is targetSellerAssets.
    /// @dev The referral fee changes the amount that must be filled, which can change the average taking price.
    function sellSellerAssetsTarget(
        address midnight,
        uint256 targetSellerAssets,
        address taker,
        address receiver,
        Take[] calldata takes,
        CollateralTransfer[] calldata collateralSupplies,
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
            SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), collateralSupplies[i].assets);
            _forceApproveMax(token, midnight);
            IMidnight(midnight)
                .supplyCollateral(
                    obligation, collateralSupplies[i].collateralIndex, collateralSupplies[i].assets, taker
                );
        }

        uint256 referralFeeAssets = targetSellerAssets.mulDivDown(referralFeePct, WAD - referralFeePct);
        uint256 targetFilledSellerAssets = targetSellerAssets + referralFeeAssets;

        uint256 filledSellerAssets;
        for (uint256 i; i < takes.length && filledSellerAssets < targetFilledSellerAssets; i++) {
            require(takes[i].offer.buy, InconsistentSide());
            require(IMidnight(midnight).toId(takes[i].offer.obligation) == id, InconsistentObligation());
            try IMidnight(midnight)
                .take(
                    UtilsLib.min(
                        TakeAmountsLib.sellerAssetsToUnits(
                            midnight, id, takes[i].offer, targetFilledSellerAssets - filledSellerAssets
                        ),
                        takes[i].units
                    ),
                    taker,
                    address(0),
                    "",
                    address(this),
                    takes[i].offer,
                    takes[i].ratifierData,
                    takes[i].root,
                    takes[i].proof
                ) returns (
                uint256, uint256 resSellerAssets, uint256
            ) {
                filledSellerAssets += resSellerAssets;
            } catch {}
        }

        require(filledSellerAssets == targetFilledSellerAssets, OutOfOffers());

        if (referralFeeAssets > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFeeAssets);
        SafeTransferLib.safeTransfer(loanToken, receiver, targetSellerAssets);
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
}
