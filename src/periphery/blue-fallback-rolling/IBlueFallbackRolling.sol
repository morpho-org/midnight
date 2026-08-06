// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IMorphoSupplyCollateralCallback} from "../../../lib/morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import {MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {Market} from "../../interfaces/IMidnight.sol";

/// @param rollWindow The duration before the Midnight market's maturity from which rolling is allowed.
/// @param incentive The share of the rolled debt paid to the caller, capped at 100%.
struct Config {
    uint64 rollWindow;
    uint64 incentive;
}

interface IBlueFallbackRolling is IMorphoSupplyCollateralCallback {
    /// ERRORS ///
    error IncentiveTooHigh();
    error IncorrectActivatedCollateral();
    error InconsistentCollateralToken();
    error InconsistentLoanToken();
    error NotBlue();
    error NotConfigured();
    error RollWindowNotOpen();

    /// EVENTS ///
    event SetConfig(
        address indexed user,
        bytes32 indexed midnightId,
        bytes32 indexed blueId,
        uint256 rollWindow,
        uint256 incentive,
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
    function setConfig(bytes32 midnightId, bytes32 blueId, Config memory config, bool enabled) external;
    function roll(
        Market memory midnightMarket,
        MarketParams memory blueMarketParams,
        address user,
        Config memory config,
        uint256 assets
    ) external;
}
