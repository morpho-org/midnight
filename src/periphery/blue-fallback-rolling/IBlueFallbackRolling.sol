// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IMorphoSupplyCollateralCallback} from "../../../lib/morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import {MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {Market} from "../../interfaces/IMidnight.sol";

interface IBlueFallbackRolling is IMorphoSupplyCollateralCallback {
    /// ERRORS ///
    error IncentiveTooHigh();
    error IncorrectActivatedCollateral();
    error InconsistentBlueMarket();
    error InconsistentCollateralToken();
    error InconsistentLoanToken();
    error InconsistentMidnightMarket();
    error NotBlue();
    error NotStarted();

    /// EVENTS ///
    event Roll(
        address indexed caller,
        address indexed user,
        bytes32 indexed midnightId,
        bytes32 blueId,
        uint256 debtAssets,
        uint256 collateralAssets,
        uint256 incentiveAssets
    );

    /// IMMUTABLE GETTERS ///
    function MIDNIGHT() external view returns (address);
    function BLUE() external view returns (address);
    function MIDNIGHT_ID() external view returns (bytes32);
    function BLUE_ID() external view returns (bytes32);
    function START() external view returns (uint64);
    function INCENTIVE() external view returns (uint64);

    /// FUNCTIONS ///
    function roll(Market memory midnightMarket, MarketParams memory blueMarketParams, address user, uint256 assets)
        external;
}
