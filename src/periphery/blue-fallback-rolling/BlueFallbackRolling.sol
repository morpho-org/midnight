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
import {IBlueFallbackRolling, Config} from "./IBlueFallbackRolling.sol";
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

    /// @param config.incentive The caller incentive as a WAD-scaled percentage of the debt rolled.
    function setConfig(Config memory config, bool enabled) external override {
        require(config.incentive <= WAD, IncentiveTooHigh());

        isConfig[msg.sender][keccak256(abi.encode(config))] = enabled;

        emit SetConfig(msg.sender, config.midnightId, config.blueId, config.start, config.incentive, enabled);
    }

    function roll(
        Market memory midnightMarket,
        MarketParams memory blueMarketParams,
        address user,
        Config memory config,
        uint256 assets
    ) external override {
        // The ids must be derived from the markets given here, not merely trusted from `config`, so that a config
        // cannot be reused to roll into a market it was not set up for.
        require(IdLib.toId(midnightMarket) == config.midnightId, InconsistentMidnightId());
        require(Id.unwrap(blueMarketParams.id()) == config.blueId, InconsistentBlueId());
        require(isConfig[user][keccak256(abi.encode(config))], NotConfigured());
        require(blueMarketParams.loanToken == midnightMarket.loanToken, InconsistentLoanToken());
        require(block.timestamp >= config.start, NotStarted());
        uint128 collateralBitmap = IMidnight(MIDNIGHT).collateralBitmap(config.midnightId, user);
        require(UtilsLib.countBits(collateralBitmap) == 1, IncorrectActivatedCollateral());
        uint256 collateralIndex = UtilsLib.msb(collateralBitmap);
        require(
            blueMarketParams.collateralToken == midnightMarket.collateralParams[collateralIndex].token,
            InconsistentCollateralToken()
        );

        // Round in favor of the Midnight position.
        uint256 collateralAssets = IMidnight(MIDNIGHT).collateral(config.midnightId, user, collateralIndex)
            .mulDivDown(assets, IMidnight(MIDNIGHT).debt(config.midnightId, user));
        // Round in favor of the borrower.
        uint256 incentiveAssets = UtilsLib.mulDivDown(assets, config.incentive, WAD);

        emit Roll(msg.sender, user, config.midnightId, config.blueId, assets, collateralAssets, incentiveAssets);

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
