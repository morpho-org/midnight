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
import {
    IBlueFallbackRolling,
    ConfigAuthorization,
    Signature,
    CONFIG_AUTHORIZATION_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "./IBlueFallbackRolling.sol";
import {SafeApproveLib} from "../libraries/SafeApproveLib.sol";

/// @dev Users must authorize this contract on both Midnight and Blue before their debt can be rolled.
contract BlueFallbackRolling is IBlueFallbackRolling {
    using MarketParamsLib for MarketParams;
    using UtilsLib for uint128;

    address public immutable override MIDNIGHT;
    address public immutable override BLUE;

    mapping(address user => mapping(bytes32 configId => bool)) public override isConfig;
    mapping(address user => uint256) public override nonce;

    constructor(address _midnight, address _blue) {
        MIDNIGHT = _midnight;
        BLUE = _blue;
    }

    /// @dev The LLTV of the Blue market must be greater than or equal to the LLTV of the Midnight market.
    function setConfig(
        bytes32 midnightId,
        bytes32 blueId,
        uint64 start,
        uint64 end,
        uint64 incentiveAtStart,
        uint64 incentiveAtEnd,
        bool enabled
    ) external override {
        _setConfig(msg.sender, midnightId, blueId, start, end, incentiveAtStart, incentiveAtEnd, enabled);
    }

    function setConfigWithSig(ConfigAuthorization memory authorization, Signature memory signature) external override {
        require(block.timestamp <= authorization.deadline, Expired());
        require(authorization.nonce == nonce[authorization.user]++, InvalidNonce());

        bytes32 hashStruct = keccak256(abi.encode(CONFIG_AUTHORIZATION_TYPEHASH, authorization));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        address signer = ecrecover(digest, signature.v, signature.r, signature.s);
        require(signer != address(0), InvalidSignature());
        require(
            signer == authorization.user || IMidnight(MIDNIGHT).isAuthorized(authorization.user, signer), Unauthorized()
        );

        emit SetConfigWithSig(msg.sender, authorization.user, authorization.nonce, signer);

        _setConfig(
            authorization.user,
            authorization.midnightId,
            authorization.blueId,
            authorization.start,
            authorization.end,
            authorization.incentiveAtStart,
            authorization.incentiveAtEnd,
            authorization.enabled
        );
    }

    function _setConfig(
        address user,
        bytes32 midnightId,
        bytes32 blueId,
        uint64 start,
        uint64 end,
        uint64 incentiveAtStart,
        uint64 incentiveAtEnd,
        bool enabled
    ) internal {
        require(start < end, EndNotAfterStart());
        require(incentiveAtStart <= WAD, IncentiveTooHigh());
        require(incentiveAtEnd <= WAD, IncentiveTooHigh());

        bytes32 configId = keccak256(abi.encode(midnightId, blueId, start, end, incentiveAtStart, incentiveAtEnd));
        isConfig[user][configId] = enabled;

        emit SetConfig(user, midnightId, blueId, start, end, incentiveAtStart, incentiveAtEnd, enabled);
    }

    function roll(
        Market memory midnightMarket,
        MarketParams memory blueMarketParams,
        address user,
        uint64 start,
        uint64 end,
        uint64 incentiveAtStart,
        uint64 incentiveAtEnd,
        uint256 assets
    ) external override {
        bytes32 midnightId = IdLib.toId(midnightMarket);
        bytes32 blueId = Id.unwrap(blueMarketParams.id());
        require(
            isConfig[user][keccak256(abi.encode(midnightId, blueId, start, end, incentiveAtStart, incentiveAtEnd))],
            NotConfigured()
        );
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
        require(midnightMarket.collateralParams[collateralIndex].lltv <= blueMarketParams.lltv, BlueLltvTooLow());

        // Round in favor of the Midnight position.
        uint256 collateralAssets = IMidnight(MIDNIGHT).collateral(midnightId, user, collateralIndex)
            .mulDivDown(assets, IMidnight(MIDNIGHT).debt(midnightId, user));
        // Round against the keeper.
        uint256 incentiveFactor = incentiveAtStart
            + UtilsLib.mulDivDown(incentiveAtEnd - incentiveAtStart, block.timestamp - start, end - start);
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
