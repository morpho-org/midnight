// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight, Obligation} from "../interfaces/IMidnight.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ITakeBundler, Take, CollateralTransfer} from "./interfaces/ITakeBundler.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";
import {TakeAmountsLib} from "./TakeAmountsLib.sol";

contract TakeBundler is ITakeBundler {
    using UtilsLib for uint256;

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    function buyUnitsTarget(
        address midnight,
        uint256 targetUnits,
        address taker,
        Take[] calldata takes,
        uint256 maxBuyerAssets,
        CollateralTransfer[] calldata collateralWithdrawals,
        address collateralReceiver,
        uint256 referralFee,
        address referralFeeRecipient
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        address loanToken = takes[0].offer.obligation.loanToken;
        bytes32 id = IMidnight(midnight).toId(takes[0].offer.obligation);

        uint256 totalFilledUnits;
        uint256 totalFilledBuyerAssets;
        for (uint256 i; i < takes.length && totalFilledUnits < targetUnits; i++) {
            require(!takes[i].offer.buy, InconsistentSide());
            require(IMidnight(midnight).toId(takes[i].offer.obligation) == id, InconsistentObligation());
            try IMidnight(midnight)
                .take(
                    UtilsLib.min(targetUnits - totalFilledUnits, takes[i].units),
                    taker,
                    address(0),
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
                totalFilledBuyerAssets += filledBuyerAssets;
            } catch {}
        }

        require(totalFilledUnits == targetUnits, InsufficientLiquidity());
        require(totalFilledBuyerAssets <= maxBuyerAssets, BuyerAssetsAboveMax());

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

        if (referralFee > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFee);
    }

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev The msg.sender should have approved the bundler to transfer enough collateral.
    function sellUnitsTarget(
        address midnight,
        uint256 targetUnits,
        address taker,
        address receiver,
        Take[] calldata takes,
        uint256 minSellerAssets,
        CollateralTransfer[] calldata collateralSupplies,
        uint256 referralFee,
        address referralFeeRecipient
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        address loanToken = takes[0].offer.obligation.loanToken;
        bytes32 id = IMidnight(midnight).toId(takes[0].offer.obligation);

        Obligation memory obligation = takes[0].offer.obligation;
        for (uint256 i; i < collateralSupplies.length; i++) {
            address token = obligation.collateralParams[collateralSupplies[i].collateralIndex].token;
            SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), collateralSupplies[i].assets);
            _safeApprove(token, midnight, collateralSupplies[i].assets);
            IMidnight(midnight)
                .supplyCollateral(
                    obligation, collateralSupplies[i].collateralIndex, collateralSupplies[i].assets, taker
                );
        }

        uint256 totalFilledSellerAssets;
        uint256 totalFilledUnits;
        for (uint256 i; i < takes.length && totalFilledUnits < targetUnits; i++) {
            require(takes[i].offer.buy, InconsistentSide());
            require(IMidnight(midnight).toId(takes[i].offer.obligation) == id, InconsistentObligation());
            try IMidnight(midnight)
                .take(
                    UtilsLib.min(targetUnits - totalFilledUnits, takes[i].units),
                    taker,
                    address(0),
                    "",
                    address(this),
                    takes[i].offer,
                    takes[i].ratifierData,
                    takes[i].root,
                    takes[i].proof
                ) returns (
                uint256, uint256 filledSellerAssets, uint256 filledUnits
            ) {
                totalFilledUnits += filledUnits;
                totalFilledSellerAssets += filledSellerAssets;
            } catch {}
        }

        require(totalFilledUnits == targetUnits, InsufficientLiquidity());
        require(totalFilledSellerAssets >= minSellerAssets, SellerAssetsBelowMin());

        if (referralFee > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFee);
        SafeTransferLib.safeTransfer(loanToken, receiver, totalFilledSellerAssets - referralFee);
    }

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev Takes could have different obligations (with the same loan token).
    function buyBuyerAssetsTarget(
        address midnight,
        uint256 targetBuyerAssets,
        address taker,
        Take[] calldata takes,
        uint256 minUnits,
        uint256 maxUnits,
        CollateralTransfer[] calldata collateralWithdrawals,
        address collateralReceiver,
        uint256 referralFee,
        address referralFeeRecipient
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        address loanToken = takes[0].offer.obligation.loanToken;
        uint256 preFeeTargetBuyerAssets = targetBuyerAssets - referralFee;

        uint256 totalFilledBuyerAssets;
        uint256 totalFilledUnits;
        for (uint256 i; i < takes.length && totalFilledBuyerAssets < preFeeTargetBuyerAssets; i++) {
            require(!takes[i].offer.buy, InconsistentSide());
            require(takes[i].offer.obligation.loanToken == loanToken, InconsistentLoanToken());
            // touchObligation to have the correct trading fees.
            bytes32 id = IMidnight(midnight).touchObligation(takes[i].offer.obligation);
            try IMidnight(midnight)
                .take(
                    UtilsLib.min(
                        TakeAmountsLib.buyerAssetsToUnits(
                            midnight, id, takes[i].offer, preFeeTargetBuyerAssets - totalFilledBuyerAssets
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
                uint256 filledBuyerAssets, uint256, uint256 filledUnits
            ) {
                totalFilledBuyerAssets += filledBuyerAssets;
                totalFilledUnits += filledUnits;
            } catch {}
        }

        require(totalFilledBuyerAssets == preFeeTargetBuyerAssets, InsufficientLiquidity());
        require(totalFilledUnits >= minUnits, UnitsBelowMin());
        require(totalFilledUnits <= maxUnits, UnitsAboveMax());

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

        if (referralFee > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFee);
    }

    /// @dev The taker must have authorized this bundler and the msg.sender (if different from the taker) on Midnight.
    /// @dev The bundler skips every reason why `take` can revert (including ones that are not asynchrony related).
    /// @dev If taking an offer reverts, the bundler will completely skip this offer.
    /// @dev The msg.sender should have approved the bundler to transfer enough collateral.
    /// @dev Takes could have different obligations (with the same loan token).
    function sellSellerAssetsTarget(
        address midnight,
        uint256 targetSellerAssets,
        address taker,
        address receiver,
        Take[] calldata takes,
        uint256 minUnits,
        uint256 maxUnits,
        CollateralTransfer[] calldata collateralSupplies,
        uint256 referralFee,
        address referralFeeRecipient
    ) external {
        require(taker == msg.sender || IMidnight(midnight).isAuthorized(taker, msg.sender), Unauthorized());
        address loanToken = takes[0].offer.obligation.loanToken;
        uint256 preFeeTargetSellerAssets = targetSellerAssets + referralFee;

        Obligation memory obligation = takes[0].offer.obligation;
        for (uint256 i; i < collateralSupplies.length; i++) {
            address token = obligation.collateralParams[collateralSupplies[i].collateralIndex].token;
            SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), collateralSupplies[i].assets);
            _safeApprove(token, midnight, collateralSupplies[i].assets);
            IMidnight(midnight)
                .supplyCollateral(
                    obligation, collateralSupplies[i].collateralIndex, collateralSupplies[i].assets, taker
                );
        }

        uint256 totalFilledSellerAssets;
        uint256 totalFilledUnits;
        for (uint256 i; i < takes.length && totalFilledSellerAssets < preFeeTargetSellerAssets; i++) {
            require(takes[i].offer.buy, InconsistentSide());
            require(takes[i].offer.obligation.loanToken == loanToken, InconsistentLoanToken());
            // touchObligation to have the correct trading fees.
            bytes32 id = IMidnight(midnight).touchObligation(takes[i].offer.obligation);
            try IMidnight(midnight)
                .take(
                    UtilsLib.min(
                        TakeAmountsLib.sellerAssetsToUnits(
                            midnight, id, takes[i].offer, preFeeTargetSellerAssets - totalFilledSellerAssets
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
                uint256, uint256 filledSellerAssets, uint256 filledUnits
            ) {
                totalFilledSellerAssets += filledSellerAssets;
                totalFilledUnits += filledUnits;
            } catch {}
        }

        require(totalFilledSellerAssets == preFeeTargetSellerAssets, InsufficientLiquidity());
        require(totalFilledUnits >= minUnits, UnitsBelowMin());
        require(totalFilledUnits <= maxUnits, UnitsAboveMax());

        if (referralFee > 0) SafeTransferLib.safeTransfer(loanToken, referralFeeRecipient, referralFee);
        SafeTransferLib.safeTransfer(loanToken, receiver, totalFilledSellerAssets - referralFee);
    }

    /// @dev USDT won't break because the allowance is reset to 0 after supplyCollateral.
    function _safeApprove(address token, address spender, uint256 value) internal {
        (bool success, bytes memory returndata) = token.call(abi.encodeCall(IERC20.approve, (spender, value)));
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returndata, 0x20), mload(returndata))
            }
        }
        require(returndata.length == 0 || abi.decode(returndata, (bool)));
    }
}
