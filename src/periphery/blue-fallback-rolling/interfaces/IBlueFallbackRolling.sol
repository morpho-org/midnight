// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IMorphoSupplyCollateralCallback} from "../../../../lib/morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import {MarketParams} from "../../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {Market} from "../../../interfaces/IMidnight.sol";

interface IBlueFallbackRolling is IMorphoSupplyCollateralCallback {
    /// ERRORS ///
    error BlueLltvTooLow();
    error Ended();
    error EndNotAfterStart();
    error IncentiveTooHigh();
    error IncorrectActivatedCollateral();
    error InconsistentCollateralToken();
    error InconsistentLoanToken();
    error NotBlue();
    error NotConfigured();
    error NotStarted();
    error RemainingDebtTooLow();
    error RollAmountTooLow();

    /// EVENTS ///
    event SetConfig(
        address indexed user,
        bytes32 indexed midnightId,
        bytes32 indexed blueId,
        uint256 start,
        uint256 end,
        uint256 incentiveAtStart,
        uint256 incentiveAtEnd,
        uint256 minRollAmount,
        bool enabled
    );
    event Roll(
        address indexed caller,
        address indexed user,
        bytes32 indexed midnightId,
        bytes32 blueId,
        uint256 debtAssets,
        uint256 collateralAssets,
        uint256 incentiveAssets
    );

    /// STORAGE GETTERS ///
    function MIDNIGHT() external view returns (address);
    function BLUE() external view returns (address);
    function isConfig(address user, bytes32 configId) external view returns (bool);

    /// FUNCTIONS ///
    function setConfig(
        bytes32 midnightId,
        bytes32 blueId,
        uint64 start,
        uint64 end,
        uint64 incentiveAtStart,
        uint64 incentiveAtEnd,
        uint256 minRollAmount,
        bool enabled
    ) external;
    function roll(
        Market memory midnightMarket,
        MarketParams memory blueMarketParams,
        address user,
        uint64 start,
        uint64 end,
        uint64 incentiveAtStart,
        uint64 incentiveAtEnd,
        uint256 minRollAmount,
        uint256 assets
    ) external;
}
