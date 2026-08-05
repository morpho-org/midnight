// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {
    IMorpho,
    Id,
    MarketParams,
    Market as BlueMarket,
    Position
} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "../../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {IMidnight, Market} from "../../interfaces/IMidnight.sol";
import {IOracle} from "../../interfaces/IOracle.sol";
import {WAD, ORACLE_PRICE_SCALE} from "../../libraries/ConstantsLib.sol";
import {IdLib} from "../../libraries/IdLib.sol";
import {SafeTransferLib} from "../../libraries/SafeTransferLib.sol";
import {UtilsLib} from "../../libraries/UtilsLib.sol";
import {IBlueFallbackRolling} from "./IBlueFallbackRolling.sol";
import {SafeApproveLib} from "../libraries/SafeApproveLib.sol";

/// @dev Users must authorize this contract on both Midnight and Blue before their debt can be rolled.
contract BlueFallbackRolling is IBlueFallbackRolling {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    using UtilsLib for uint128;
    using UtilsLib for uint256;

    address public immutable override MIDNIGHT;
    address public immutable override BLUE;

    mapping(address user => mapping(bytes32 configId => bool)) public override isConfig;

    constructor(address _midnight, address _blue) {
        MIDNIGHT = _midnight;
        BLUE = _blue;
    }

    /// @param start The start time of the rolling window.
    /// @param incentive The caller incentive as a WAD-scaled percentage of the debt rolled.
    /// @param maxLtv The maximum LTV allowed for the Blue position after the roll.
    function setConfig(bytes32 midnightId, bytes32 blueId, uint64 start, uint64 incentive, uint256 maxLtv, bool enabled)
        external
        override
    {
        require(incentive <= WAD, IncentiveTooHigh());

        isConfig[msg.sender][keccak256(abi.encode(midnightId, blueId, start, incentive, maxLtv))] = enabled;

        emit SetConfig(msg.sender, midnightId, blueId, start, incentive, maxLtv, enabled);
    }

    function roll(
        Market memory midnightMarket,
        MarketParams memory blueMarketParams,
        address user,
        uint64 start,
        uint64 incentive,
        uint256 maxLtv,
        uint256 assets
    ) external override {
        require(maxLtv <= blueMarketParams.lltv, InvalidMaxLtv());
        bytes32 midnightId = IdLib.toId(midnightMarket);
        bytes32 blueId = Id.unwrap(blueMarketParams.id());
        require(isConfig[user][keccak256(abi.encode(midnightId, blueId, start, incentive, maxLtv))], NotConfigured());
        require(blueMarketParams.loanToken == midnightMarket.loanToken, InconsistentLoanToken());
        require(block.timestamp >= start, NotStarted());
        uint128 collateralBitmap = IMidnight(MIDNIGHT).collateralBitmap(midnightId, user);
        require(UtilsLib.countBits(collateralBitmap) == 1, IncorrectActivatedCollateral());
        uint256 collateralIndex = UtilsLib.msb(collateralBitmap);
        require(
            blueMarketParams.collateralToken == midnightMarket.collateralParams[collateralIndex].token,
            InconsistentCollateralToken()
        );

        // Round in favor of the Midnight position.
        uint256 collateralAssets = IMidnight(MIDNIGHT).collateral(midnightId, user, collateralIndex)
            .mulDivDown(assets, IMidnight(MIDNIGHT).debt(midnightId, user));
        // Round in favor of the borrower.
        uint256 incentiveAssets = UtilsLib.mulDivDown(assets, incentive, WAD);

        emit Roll(msg.sender, user, midnightId, blueId, assets, collateralAssets, incentiveAssets);

        bytes memory data = abi.encode(midnightMarket, blueMarketParams, collateralIndex, assets, incentiveAssets, user);
        IMorpho(BLUE).supplyCollateral(blueMarketParams, collateralAssets, user, data);
        if (incentiveAssets > 0) SafeTransferLib.safeTransfer(midnightMarket.loanToken, msg.sender, incentiveAssets);

        requireMaxLtv(blueMarketParams, user, maxLtv);
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

    function requireMaxLtv(MarketParams memory marketParams, address sender, uint256 maxLtv) internal view {
        Position memory position = IMorpho(BLUE).position(marketParams.id(), sender);
        if (position.borrowShares == 0) return;
        BlueMarket memory market = IMorpho(BLUE).market(marketParams.id());
        uint256 borrowed = uint256(position.borrowShares).toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
        uint256 price = IOracle(marketParams.oracle).price();
        uint256 maxBorrow = uint256(position.collateral).mulDivDown(price, ORACLE_PRICE_SCALE).mulDivDown(maxLtv, WAD);
        require(borrowed <= maxBorrow, LtvExceeded());
    }
}
