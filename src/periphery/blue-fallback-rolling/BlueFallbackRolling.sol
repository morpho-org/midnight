// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IMorpho, Id, MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IRepayCallback} from "../../interfaces/ICallbacks.sol";
import {IMidnight, Market} from "../../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS, WAD} from "../../libraries/ConstantsLib.sol";
import {IdLib} from "../../libraries/IdLib.sol";
import {SafeTransferLib} from "../../libraries/SafeTransferLib.sol";
import {UtilsLib} from "../../libraries/UtilsLib.sol";
import {IBlueFallbackRolling} from "./IBlueFallbackRolling.sol";
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

    /// @param start The start time of the rolling period.
    /// @param end The end time of the rolling period.
    /// @param incentiveAtStart The caller incentive at `start`, as a WAD-scaled percentage of the debt rolled. It must
    /// be greater than or equal to `-WAD`: a negative incentive is a premium that the caller pays instead, which is
    /// repaid on Blue on behalf of the user.
    /// @param incentiveAtEnd The caller incentive at `end`, as a WAD-scaled percentage of the debt rolled. The
    /// incentive is auctioned off between the two: see `incentive`.
    /// @dev The LLTV of the Blue market must be greater than or equal to the LLTV of the Midnight market.
    function setConfig(
        bytes32 midnightId,
        bytes32 blueId,
        uint64 start,
        uint64 end,
        int256 incentiveAtStart,
        int256 incentiveAtEnd,
        bool enabled
    ) external override {
        require(start <= end, EndBeforeStart());
        require(incentiveAtStart >= -int256(WAD), IncentiveTooLow());
        require(incentiveAtStart <= incentiveAtEnd, IncentiveNotIncreasing());
        require(incentiveAtEnd <= int256(WAD), IncentiveTooHigh());

        isConfig[msg.sender][keccak256(abi.encode(midnightId, blueId, start, end, incentiveAtStart, incentiveAtEnd))] =
            enabled;

        emit SetConfig(msg.sender, midnightId, blueId, start, end, incentiveAtStart, incentiveAtEnd, enabled);
    }

    /// @notice The caller incentive at the current timestamp, as a WAD-scaled percentage of the debt rolled.
    /// @dev The incentive is auctioned off: it grows linearly from `incentiveAtStart` at `start` to `incentiveAtEnd` at
    /// `end`, and stays at `incentiveAtEnd` afterwards.
    function incentive(uint64 start, uint64 end, int256 incentiveAtStart, int256 incentiveAtEnd)
        public
        view
        override
        returns (int256)
    {
        if (block.timestamp >= end) return incentiveAtEnd;
        if (block.timestamp <= start) return incentiveAtStart;
        uint256 elapsed = block.timestamp - start;
        uint256 duration = end - start;
        // Round in favor of the borrower: the incentive increases over the auction, so the division truncates the
        // interpolated growth downwards.
        return incentiveAtStart + (incentiveAtEnd - incentiveAtStart) * int256(elapsed) / int256(duration);
    }

    /// @param data Arbitrary data passed back to the caller during the Midnight repayment, through its `onRepay`. It
    /// must be empty for a caller that does not implement `IRepayCallback`, such as an EOA: no callback is then made.
    function roll(
        Market memory midnightMarket,
        MarketParams memory blueMarketParams,
        address user,
        uint64 start,
        uint64 end,
        int256 incentiveAtStart,
        int256 incentiveAtEnd,
        uint256 assets,
        bytes calldata data
    ) external override {
        bytes32 midnightId = IdLib.toId(midnightMarket);
        bytes32 blueId = Id.unwrap(blueMarketParams.id());
        require(
            isConfig[user][keccak256(abi.encode(midnightId, blueId, start, end, incentiveAtStart, incentiveAtEnd))],
            NotConfigured()
        );
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
        int256 incentiveWad = incentive(start, end, incentiveAtStart, incentiveAtEnd);
        // Round in favor of the borrower: down when the caller is paid, up in magnitude when the caller pays.
        int256 incentiveAssets = incentiveWad >= 0
            ? int256(UtilsLib.mulDivDown(assets, uint256(incentiveWad), WAD))
            : -int256(UtilsLib.mulDivUp(assets, uint256(-incentiveWad), WAD));

        emit Roll(msg.sender, user, midnightId, blueId, assets, collateralAssets, incentiveAssets);

        uint256 borrowAssets = incentiveAssets >= 0 ? assets + uint256(incentiveAssets) : assets;
        bytes memory blueData =
            abi.encode(midnightMarket, blueMarketParams, collateralIndex, assets, borrowAssets, user, msg.sender, data);
        IMorpho(BLUE).supplyCollateral(blueMarketParams, collateralAssets, user, blueData);

        if (incentiveAssets > 0) {
            SafeTransferLib.safeTransfer(midnightMarket.loanToken, msg.sender, uint256(incentiveAssets));
        } else if (incentiveAssets < 0) {
            uint256 premiumAssets = uint256(-incentiveAssets);
            SafeTransferLib.safeTransferFrom(midnightMarket.loanToken, msg.sender, address(this), premiumAssets);
            SafeApproveLib.forceApproveMax(blueMarketParams.loanToken, BLUE);
            IMorpho(BLUE).repay(blueMarketParams, premiumAssets, 0, user, hex"");
        }
    }

    function onMorphoSupplyCollateral(uint256 collateralAssets, bytes calldata data) external {
        require(msg.sender == BLUE, NotBlue());

        (
            Market memory midnightMarket,
            MarketParams memory blueMarketParams,
            uint256 collateralIndex,
            uint256 assets,
            uint256 borrowAssets,
            address user,
            address caller,
            bytes memory callerData
        ) = abi.decode(data, (Market, MarketParams, uint256, uint256, uint256, address, address, bytes));

        IMorpho(BLUE).borrow(blueMarketParams, borrowAssets, 0, user, address(this));
        SafeApproveLib.forceApproveMax(midnightMarket.loanToken, MIDNIGHT);
        // Passing this contract as the repayment callback keeps it the payer, and lets it call the caller back. Without
        // caller data, no callback is needed, so the repayment is made without one.
        if (callerData.length > 0) {
            IMidnight(MIDNIGHT).repay(midnightMarket, assets, user, address(this), abi.encode(caller, callerData));
        } else {
            IMidnight(MIDNIGHT).repay(midnightMarket, assets, user, address(0), hex"");
        }
        IMidnight(MIDNIGHT).withdrawCollateral(midnightMarket, collateralIndex, collateralAssets, user, address(this));
        SafeApproveLib.forceApproveMax(blueMarketParams.collateralToken, BLUE);
    }

    /// @dev Forwards the Midnight repayment callback to the caller of `roll`, so that it can run its own logic within
    /// the roll. This contract remains the payer of the repayment, so the caller is not expected to fund it.
    function onRepay(bytes32 id, Market memory market, uint256 units, address onBehalf, bytes memory data)
        external
        override
        returns (bytes32)
    {
        require(msg.sender == MIDNIGHT, NotMidnight());

        (address caller, bytes memory callerData) = abi.decode(data, (address, bytes));
        require(
            IRepayCallback(caller).onRepay(id, market, units, onBehalf, callerData) == CALLBACK_SUCCESS,
            WrongRollerCallbackReturnValue()
        );

        return CALLBACK_SUCCESS;
    }
}
