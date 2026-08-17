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

    /// @dev The caller must be `user` or an address authorized for `user` on Midnight.
    /// @dev `minRollableAssets` is the minimum debt that a single roll can move to Blue, unless the roll moves the
    /// whole remaining Midnight debt.
    function setConfig(
        address user,
        bytes32 midnightId,
        bytes32 blueId,
        uint64 start,
        uint64 end,
        uint64 incentiveAtStart,
        uint64 incentiveAtEnd,
        uint128 minRollableAssets,
        bool enabled
    ) external override {
        require(start < end, EndNotAfterStart());
        require(incentiveAtStart <= WAD, IncentiveTooHigh());
        require(incentiveAtEnd <= WAD, IncentiveTooHigh());

        require(msg.sender == user || IMidnight(MIDNIGHT).isAuthorized(user, msg.sender), Unauthorized());

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

    function roll(
        Market memory midnightMarket,
        MarketParams memory blueMarketParams,
        address user,
        uint64 start,
        uint64 end,
        uint64 incentiveAtStart,
        uint64 incentiveAtEnd,
        uint128 minRollableAssets,
        uint256 assets
    ) external override {
        bytes32 midnightId = IdLib.toId(midnightMarket);
        bytes32 blueId = Id.unwrap(blueMarketParams.id());
        bytes32 configId =
            keccak256(abi.encode(midnightId, blueId, start, end, incentiveAtStart, incentiveAtEnd, minRollableAssets));
        require(isConfig[user][configId], NotConfigured());
        require(blueMarketParams.loanToken == midnightMarket.loanToken, InconsistentLoanToken());
        require(block.timestamp >= start, NotStarted());
        require(block.timestamp <= end, Ended());
        uint128 collateralBitmap = IMidnight(MIDNIGHT).collateralBitmap(midnightId, user);
        require(UtilsLib.countBits(collateralBitmap) == 1, IncorrectActivatedCollateral());
        uint256 collateralIndex = UtilsLib.msb(collateralBitmap);
        require(
            blueMarketParams.collateralToken == midnightMarket.collateralParams[collateralIndex].token,
            InconsistentCollateralToken()
        );

        uint256 debtAssets = IMidnight(MIDNIGHT).debt(midnightId, user);
        require(assets >= minRollableAssets || assets == debtAssets, RollableAssetsTooLow());

        // Round in favor of the Midnight position. Thus, splitting the rolls can lower the blue final LTV. This is
        // mitigated by the min rollable debt.
        uint256 collateralAssets =
            IMidnight(MIDNIGHT).collateral(midnightId, user, collateralIndex).mulDivDown(assets, debtAssets);
        // Round against the roller.
        uint256 incentiveFactor = incentiveAtEnd >= incentiveAtStart
            ? incentiveAtStart
                + UtilsLib.mulDivDown(incentiveAtEnd - incentiveAtStart, block.timestamp - start, end - start)
            : incentiveAtStart
                - UtilsLib.mulDivUp(incentiveAtStart - incentiveAtEnd, block.timestamp - start, end - start);
        uint256 incentiveAssets = UtilsLib.mulDivDown(assets, incentiveFactor, WAD);

        emit Roll(msg.sender, user, midnightId, blueId, assets, collateralAssets, incentiveAssets);

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
