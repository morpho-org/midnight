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
import {IBlueFallbackRolling} from "./interfaces/IBlueFallbackRolling.sol";
import {SafeApproveLib} from "../libraries/SafeApproveLib.sol";

/// @dev Users must authorize this contract on both Midnight and Blue before their debt can be rolled.
/// @dev Users must make sure that the oracle and the LLTV of the Blue market are appropriate; otherwise, their
/// position on Blue could be left close to liquidation.
/// @dev The rolling incentive corresponds to the percentage of the debt repaid on Midnight that is given as incentive
/// equivalent to added interest on Blue.
/// @dev The rolling incentive cap at 100% is arbitrary from a technical POV.
/// @dev The source position can move before it is rolled, notably if the borrower has outstanding sell offers, in
/// which case the destination position debt and collateral can be difficult to predict.
/// @dev Contrary to Midnight, Blue positions can be liquidated because of interest accrual, which should be taken into
/// account when deciding/approving the rolling configuration.
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

    /// @dev The caller must be user or an address authorized for user on Midnight.
    function setConfig(
        address user,
        bytes32 midnightId,
        bytes32 blueId,
        uint256 start,
        uint256 end,
        uint256 incentiveAtStart,
        uint256 incentiveAtEnd,
        uint256 minRollableAssets,
        bool enabled
    ) external override {
        require(msg.sender == user || IMidnight(MIDNIGHT).isAuthorized(user, msg.sender), Unauthorized());
        require(start < end, EndNotAfterStart());
        require(incentiveAtEnd <= WAD, IncentiveTooHigh());
        require(incentiveAtEnd >= incentiveAtStart, DecreasingIncentive());

        bytes32 configId =
            keccak256(abi.encode(midnightId, blueId, start, end, incentiveAtStart, incentiveAtEnd, minRollableAssets));
        isConfig[user][configId] = enabled;

        emit SetConfig(
            msg.sender,
            user,
            midnightId,
            blueId,
            start,
            end,
            incentiveAtStart,
            incentiveAtEnd,
            minRollableAssets,
            enabled
        );
    }

    /// @dev A roll cannot be performed from inside a take's callback on the position, which prevents manipulating the
    /// collateral amount that is moved.
    function roll(
        Market memory midnightMarket,
        MarketParams memory blueMarketParams,
        address user,
        uint256 start,
        uint256 end,
        uint256 incentiveAtStart,
        uint256 incentiveAtEnd,
        uint256 minRollableAssets,
        uint256 assets
    ) external override {
        bytes32 midnightId = IdLib.toId(midnightMarket);
        bytes32 blueId = Id.unwrap(blueMarketParams.id());
        bytes32 configId =
            keccak256(abi.encode(midnightId, blueId, start, end, incentiveAtStart, incentiveAtEnd, minRollableAssets));
        require(isConfig[user][configId], NotConfigured());
        require(block.timestamp >= start, NotStarted());
        require(block.timestamp <= end, Ended());
        require(!IMidnight(MIDNIGHT).liquidationLocked(midnightId, user), LiquidationLocked());
        uint128 collateralBitmap = IMidnight(MIDNIGHT).collateralBitmap(midnightId, user);
        require(UtilsLib.countBits(collateralBitmap) == 1, IncorrectActivatedCollateral());
        uint256 collateralIndex = UtilsLib.msb(collateralBitmap);
        require(
            blueMarketParams.collateralToken == midnightMarket.collateralParams[collateralIndex].token,
            InconsistentCollateralToken()
        );
        require(blueMarketParams.loanToken == midnightMarket.loanToken, InconsistentLoanToken());

        uint256 debtAssets = IMidnight(MIDNIGHT).debt(midnightId, user);
        require(assets >= minRollableAssets || assets == debtAssets, RolledAssetsTooLow());

        // collateralAssets is rounded down, so the share of the collateral leaving the Midnight position can be less
        // than the share of debt being rolled, at the expense of the resulting Blue position. minRollableAssets
        // mitigates this by limiting how many times the rounding can be applied.
        uint256 collateralAssets =
            IMidnight(MIDNIGHT).collateral(midnightId, user, collateralIndex).mulDivDown(assets, debtAssets);
        // Round against the roller.
        uint256 incentiveFactor = incentiveAtStart
            + UtilsLib.mulDivDown(incentiveAtEnd - incentiveAtStart, block.timestamp - start, end - start);
        uint256 incentiveAssets = UtilsLib.mulDivDown(assets, incentiveFactor, WAD);

        emit Roll(msg.sender, user, midnightId, blueId, configId, assets, collateralAssets, incentiveAssets);

        bytes memory data = abi.encode(midnightMarket, blueMarketParams, collateralIndex, assets, incentiveAssets, user);
        IMorpho(BLUE).supplyCollateral(blueMarketParams, collateralAssets, user, data);
        if (incentiveAssets > 0) SafeTransferLib.safeTransfer(midnightMarket.loanToken, msg.sender, incentiveAssets);
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
