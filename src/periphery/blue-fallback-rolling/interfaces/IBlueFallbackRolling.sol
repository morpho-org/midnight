// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IMorphoSupplyCollateralCallback} from "../../../../lib/morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import {MarketParams} from "../../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {Market} from "../../../interfaces/IMidnight.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "../../ecrecover-authorizer/interfaces/IEcrecoverAuthorizer.sol";

struct ConfigAuthorization {
    address user;
    bytes32 midnightId;
    bytes32 blueId;
    uint64 start;
    uint64 end;
    uint64 incentiveAtStart;
    uint64 incentiveAtEnd;
    uint128 minRollableAssets;
    bool enabled;
    uint256 nonce;
    uint256 deadline;
}

/// @dev keccak256("ConfigAuthorization(address user,bytes32 midnightId,bytes32 blueId,uint64 start,uint64 end,uint64
/// incentiveAtStart,uint64 incentiveAtEnd,uint128 minRollableAssets,bool enabled,uint256 nonce,uint256 deadline)").
bytes32 constant CONFIG_AUTHORIZATION_TYPEHASH = 0x92769d8db36304fbf313a8dc7e38d4e05414d6483992c440ee40fbbe8c6a97ba;

interface IBlueFallbackRolling is IMorphoSupplyCollateralCallback {
    /// ERRORS ///
    error BlueLltvTooLow();
    error Ended();
    error EndNotAfterStart();
    error Expired();
    error IncentiveTooHigh();
    error IncorrectActivatedCollateral();
    error InconsistentCollateralToken();
    error InconsistentLoanToken();
    error InvalidNonce();
    error InvalidSignature();
    error NotBlue();
    error NotConfigured();
    error NotStarted();
    error RollableAssetsTooLow();
    error Unauthorized();

    /// EVENTS ///
    event SetConfig(
        address indexed user,
        bytes32 indexed midnightId,
        bytes32 indexed blueId,
        uint256 start,
        uint256 end,
        uint256 incentiveAtStart,
        uint256 incentiveAtEnd,
        uint256 minRollableAssets,
        bool enabled
    );
    event SetConfigWithSig(address indexed caller, address indexed user, uint256 nonce, address signer);
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
    function nonce(address user) external view returns (uint256);

    /// FUNCTIONS ///
    function setConfig(
        bytes32 midnightId,
        bytes32 blueId,
        uint64 start,
        uint64 end,
        uint64 incentiveAtStart,
        uint64 incentiveAtEnd,
        uint128 minRollableAssets,
        bool enabled
    ) external;
    function setConfigWithSig(ConfigAuthorization memory authorization, Signature memory signature) external;
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
    ) external;
}
