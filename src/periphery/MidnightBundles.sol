// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight, Obligation} from "../interfaces/IMidnight.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IMidnightBundles, Take, CollateralTransfer} from "./interfaces/IMidnightBundles.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";

contract MidnightBundles is IMidnightBundles {
    using UtilsLib for uint256;

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
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
                    takes[i].ratifierData
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
    /// @dev The receiver will receive at least minSellerAssets.
    /// @dev Total receipt is filledSellerAssets - filledSellerAssets * pct / WAD.
    function supplyCollateralAndSellWithUnitsTarget(
        address midnight,
        uint256 targetUnits,
        uint256 minSellerAssets,
        address taker,
        address receiver,
        Take[] calldata takes,
        CollateralTransfer[] calldata collateralSupplies,
        uint256 referralFeePct,
        address referralFeeRecipient
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        require(referralFeePct < WAD, PctExceeded());
        bytes32 id = IMidnight(midnight).toId(takes[0].offer.obligation);

        for (uint256 i; i < collateralSupplies.length; i++) {
            address token = takes[0].offer.obligation.collateralParams[collateralSupplies[i].collateralIndex].token;
            SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), collateralSupplies[i].assets);
            _forceApproveMax(token, midnight);
            IMidnight(midnight)
                .supplyCollateral(
                    takes[0].offer.obligation,
                    collateralSupplies[i].collateralIndex,
                    collateralSupplies[i].assets,
                    taker
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
                    takes[i].ratifierData
                ) returns (
                uint256, uint256 resSellerAssets, uint256 resUnits
            ) {
                filledUnits += resUnits;
                filledSellerAssets += resSellerAssets;
            } catch {}
        }

        require(filledUnits == targetUnits, OutOfOffers());

        uint256 referralFeeAssets = filledSellerAssets.mulDivDown(referralFeePct, WAD);
        require(filledSellerAssets - referralFeeAssets >= minSellerAssets, SellerAssetsTooLow());
        address loanToken = takes[0].offer.obligation.loanToken;
        if (referralFeeAssets > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFeeAssets);
        SafeTransferLib.safeTransfer(loanToken, receiver, filledSellerAssets - referralFeeAssets);
    }

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
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
        uint256 filledUnits;
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
                    takes[i].ratifierData
                ) returns (
                uint256 resBuyerAssets, uint256, uint256 resUnits
            ) {
                filledBuyerAssets += resBuyerAssets;
                filledUnits += resUnits;
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

        if (referralFeeAssets > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFeeAssets);
    }

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
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
        Take[] calldata takes,
        CollateralTransfer[] calldata collateralSupplies,
        uint256 referralFeePct,
        address referralFeeRecipient
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        require(referralFeePct < WAD, PctExceeded());
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
        uint256 filledUnits;
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
                    takes[i].ratifierData
                ) returns (
                uint256, uint256 resSellerAssets, uint256 resUnits
            ) {
                filledSellerAssets += resSellerAssets;
                filledUnits += resUnits;
            } catch {}
        }

        require(filledSellerAssets == targetFilledSellerAssets, OutOfOffers());
        require(filledUnits <= maxUnits, UnitsTooHigh());

        address loanToken = takes[0].offer.obligation.loanToken;
        if (referralFeeAssets > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFeeAssets);
        SafeTransferLib.safeTransfer(loanToken, receiver, targetSellerAssets);
    }

    /// @dev The onBehalf must have authorized this contract and the msg.sender (if different from onBehalf) on
    /// Midnight.
    /// @dev The msg.sender must have approved the contract to transfer `units` of the obligation's loan token.
    function repayAndWithdrawCollateral(
        address midnight,
        Obligation calldata obligation,
        uint256 units,
        address onBehalf,
        CollateralTransfer[] calldata collateralWithdrawals,
        address collateralReceiver
    ) external {
        require(onBehalf == msg.sender || IMidnight(midnight).isAuthorized(onBehalf, msg.sender), Unauthorized());

        address loanToken = obligation.loanToken;
        SafeTransferLib.safeTransferFrom(loanToken, msg.sender, address(this), units);
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
