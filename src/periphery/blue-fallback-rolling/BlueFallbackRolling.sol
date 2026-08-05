// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IMorpho, Id, MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IMidnight, Market} from "../../interfaces/IMidnight.sol";
import {WAD} from "../../libraries/ConstantsLib.sol";
import {IdLib} from "../../libraries/IdLib.sol";
import {SafeTransferLib} from "../../libraries/SafeTransferLib.sol";
import {UtilsLib} from "../../libraries/UtilsLib.sol";
import {CollateralRoll, IBlueFallbackRolling} from "./IBlueFallbackRolling.sol";
import {SafeApproveLib} from "../libraries/SafeApproveLib.sol";

/// @dev Users must authorize this contract on both Midnight and Blue before their debt can be rolled.
contract BlueFallbackRolling is IBlueFallbackRolling {
    using MarketParamsLib for MarketParams;
    using UtilsLib for uint128;

    address public immutable override MIDNIGHT;
    address public immutable override BLUE;

    mapping(address user => mapping(bytes32 configId => bool)) public override isConfig;

    constructor(address _midnight, address _blue) {
        MIDNIGHT = _midnight;
        BLUE = _blue;
    }

    /// @param incentive The caller incentive as a WAD-scaled percentage of the debt rolled.
    function setConfig(bytes32 midnightId, bytes32 blueId, uint64 start, uint64 incentive, bool enabled)
        external
        override
    {
        require(incentive <= WAD, IncentiveTooHigh());

        isConfig[msg.sender][keccak256(abi.encode(midnightId, blueId, start, incentive))] = enabled;

        emit SetConfig(msg.sender, midnightId, blueId, start, incentive, enabled);
    }

    /// @dev Each leg targets one of the user's activated Midnight collaterals and rolls it into its own Blue market.
    /// @dev `fraction` is a single WAD-scaled fraction of the position applied identically to every leg: each leg
    /// withdraws that same fraction of its own Midnight collateral, so the caller can only choose how much of the
    /// position to close, never the relative amounts moved between collaterals. Legs must cover every activated
    /// collateral, so the caller cannot choose a subset either. The debt being closed is split evenly by leg count
    /// so that no single leg's borrow depends on another leg's execution.
    function roll(
        Market memory midnightMarket,
        address user,
        uint64 start,
        uint64 incentive,
        uint256 fraction,
        CollateralRoll[] memory legs
    ) external override {
        require(legs.length > 0, NoCollateralLegs());
        require(block.timestamp >= start, NotStarted());
        require(fraction <= WAD, FractionTooHigh());

        bytes32 midnightId = IdLib.toId(midnightMarket);
        uint128 collateralBitmap = IMidnight(MIDNIGHT).collateralBitmap(midnightId, user);
        uint128 seenBitmap;
        uint256 totalIncentiveAssets;
        // Round in favor of the Midnight position.
        uint256 assetsPerLeg = IMidnight(MIDNIGHT).debt(midnightId, user).mulDivDown(fraction, WAD) / legs.length;

        for (uint256 i; i < legs.length; ++i) {
            CollateralRoll memory leg = legs[i];
            uint256 collateralIndex = leg.collateralIndex;
            uint128 collateralBit = uint128(1) << collateralIndex;

            require(collateralBitmap & collateralBit != 0, IncorrectActivatedCollateral());
            require(seenBitmap & collateralBit == 0, DuplicateCollateralIndex());
            seenBitmap |= collateralBit;

            bytes32 blueId = Id.unwrap(leg.blueMarketParams.id());
            require(isConfig[user][keccak256(abi.encode(midnightId, blueId, start, incentive))], NotConfigured());
            require(leg.blueMarketParams.loanToken == midnightMarket.loanToken, InconsistentLoanToken());
            require(
                leg.blueMarketParams.collateralToken == midnightMarket.collateralParams[collateralIndex].token,
                InconsistentCollateralToken()
            );

            // Round in favor of the Midnight position.
            uint256 collateralAssets =
                IMidnight(MIDNIGHT).collateral(midnightId, user, collateralIndex).mulDivDown(fraction, WAD);
            // Round in favor of the borrower.
            uint256 incentiveAssets = UtilsLib.mulDivDown(assetsPerLeg, incentive, WAD);
            totalIncentiveAssets += incentiveAssets;

            emit Roll(msg.sender, user, midnightId, blueId, assetsPerLeg, collateralAssets, incentiveAssets);

            bytes memory data = abi.encode(
                midnightMarket, leg.blueMarketParams, collateralIndex, assetsPerLeg, incentiveAssets, user
            );
            IMorpho(BLUE).supplyCollateral(leg.blueMarketParams, collateralAssets, user, data);
        }

        require(seenBitmap == collateralBitmap, MissingCollateralLeg());

        if (totalIncentiveAssets > 0) {
            SafeTransferLib.safeTransfer(midnightMarket.loanToken, msg.sender, totalIncentiveAssets);
        }
    }

    function onMorphoSupplyCollateral(uint256 collateralAssets, bytes calldata data) external {
        require(msg.sender == BLUE, NotBlue());

        (
            Market memory midnightMarket,
            MarketParams memory blueMarketParams,
            uint256 collateralIndex,
            uint256 assets,
            uint256 incentiveAssets,
            address user
        ) = abi.decode(data, (Market, MarketParams, uint256, uint256, uint256, address));

        IMorpho(BLUE).borrow(blueMarketParams, assets + incentiveAssets, 0, user, address(this));
        SafeApproveLib.forceApproveMax(midnightMarket.loanToken, MIDNIGHT);
        IMidnight(MIDNIGHT).repay(midnightMarket, assets, user, address(0), hex"");
        IMidnight(MIDNIGHT).withdrawCollateral(midnightMarket, collateralIndex, collateralAssets, user, address(this));
        SafeApproveLib.forceApproveMax(blueMarketParams.collateralToken, BLUE);
    }
}
