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
import {IBlueFallbackRolling} from "./IBlueFallbackRolling.sol";
import {SafeApproveLib} from "../libraries/SafeApproveLib.sol";

/// @dev This contract rolls debt from a single Midnight market to a single Blue market, under fixed terms.
/// @dev Users opt in by authorizing this contract on both Midnight and Blue, and opt out by revoking either
/// authorization. There is no other configuration: because the terms are immutable, the authorization can only ever
/// result in the roll defined by this contract.
contract BlueFallbackRolling is IBlueFallbackRolling {
    using MarketParamsLib for MarketParams;
    using UtilsLib for uint128;

    address public immutable override MIDNIGHT;
    address public immutable override BLUE;
    bytes32 public immutable override MIDNIGHT_ID;
    bytes32 public immutable override BLUE_ID;
    /// @dev The start time of the rolling period.
    uint64 public immutable override START;
    /// @dev The caller incentive as a WAD-scaled percentage of the debt rolled.
    uint64 public immutable override INCENTIVE;

    /// @dev The LLTV of the Blue market must be greater than or equal to the LLTV of the Midnight market.
    constructor(
        address _midnight,
        address _blue,
        bytes32 _midnightId,
        bytes32 _blueId,
        uint64 _start,
        uint64 _incentive
    ) {
        require(_incentive <= WAD, IncentiveTooHigh());

        MIDNIGHT = _midnight;
        BLUE = _blue;
        MIDNIGHT_ID = _midnightId;
        BLUE_ID = _blueId;
        START = _start;
        INCENTIVE = _incentive;
    }

    function roll(Market memory midnightMarket, MarketParams memory blueMarketParams, address user, uint256 assets)
        external
        override
    {
        bytes32 midnightId = IdLib.toId(midnightMarket);
        bytes32 blueId = Id.unwrap(blueMarketParams.id());
        require(midnightId == MIDNIGHT_ID, InconsistentMidnightMarket());
        require(blueId == BLUE_ID, InconsistentBlueMarket());
        require(blueMarketParams.loanToken == midnightMarket.loanToken, InconsistentLoanToken());
        require(block.timestamp >= START, NotStarted());
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
        uint256 incentiveAssets = UtilsLib.mulDivDown(assets, INCENTIVE, WAD);

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
