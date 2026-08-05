// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IMorphoSupplyCollateralCallback} from "../../../lib/morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import {MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {Market} from "../../interfaces/IMidnight.sol";

struct CollateralRoll {
    uint256 collateralIndex;
    MarketParams blueMarketParams;
    uint256 assets;
}

interface IBlueFallbackRolling is IMorphoSupplyCollateralCallback {
    /// ERRORS ///
    error DuplicateCollateralIndex();
    error IncentiveTooHigh();
    error IncorrectActivatedCollateral();
    error InconsistentCollateralToken();
    error InconsistentLoanToken();
    error NoCollateralLegs();
    error NotBlue();
    error NotConfigured();
    error NotStarted();

    /// EVENTS ///
    event SetConfig(
        address indexed user,
        bytes32 indexed midnightId,
        bytes32 indexed blueId,
        uint256 start,
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
    function setConfig(bytes32 midnightId, bytes32 blueId, uint64 start, uint64 incentive, bool enabled) external;
    function roll(
        Market memory midnightMarket,
        address user,
        uint64 start,
        uint64 incentive,
        CollateralRoll[] memory legs
    ) external;
}
