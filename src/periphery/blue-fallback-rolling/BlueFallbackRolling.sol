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
    ConfigSigStruct,
    Signature,
    CONFIG_SIG_STRUCT_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "./interfaces/IBlueFallbackRolling.sol";
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
    /// @dev `minRollableAssets` is the minimum debt that a single roll can move to Blue. It does not apply once the
    /// remaining Midnight debt is at most `minRollableAssets`, in which case any amount can be rolled. Setting
    /// `minRollableAssets` above the Midnight debt thus disables the constraint entirely.
    function setConfig(
        bytes32 midnightId,
        bytes32 blueId,
        uint64 start,
        uint64 end,
        uint64 incentiveAtStart,
        uint64 incentiveAtEnd,
        uint128 minRollableAssets,
        bool enabled
    ) external override {
        require(start < end, EndNotAfterStart());
        require(incentiveAtStart <= WAD, IncentiveTooHigh());
        require(incentiveAtEnd <= WAD, IncentiveTooHigh());

        bytes32 configId =
            keccak256(abi.encode(midnightId, blueId, start, end, incentiveAtStart, incentiveAtEnd, minRollableAssets));
        isConfig[msg.sender][configId] = enabled;

        emit SetConfig(
            msg.sender, midnightId, blueId, start, end, incentiveAtStart, incentiveAtEnd, minRollableAssets, enabled
        );
    }

    function setConfigWithSig(ConfigSigStruct memory signedStruct, Signature memory signature) external override {
        require(signedStruct.start < signedStruct.end, EndNotAfterStart());
        require(signedStruct.incentiveAtStart <= WAD, IncentiveTooHigh());
        require(signedStruct.incentiveAtEnd <= WAD, IncentiveTooHigh());

        require(block.timestamp <= signedStruct.deadline, Expired());
        require(signedStruct.nonce == nonce[signedStruct.user]++, InvalidNonce());

        bytes32 hashStruct = keccak256(abi.encode(CONFIG_SIG_STRUCT_TYPEHASH, signedStruct));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        address signer = ecrecover(digest, signature.v, signature.r, signature.s);
        require(signer != address(0), InvalidSignature());
        require(
            signer == signedStruct.user || IMidnight(MIDNIGHT).isAuthorized(signedStruct.user, signer), Unauthorized()
        );

        emit SetConfigWithSig(msg.sender, signedStruct.user, signedStruct.nonce, signer);

        bytes32 configId = keccak256(
            abi.encode(
                signedStruct.midnightId,
                signedStruct.blueId,
                signedStruct.start,
                signedStruct.end,
                signedStruct.incentiveAtStart,
                signedStruct.incentiveAtEnd,
                signedStruct.minRollableAssets
            )
        );
        isConfig[signedStruct.user][configId] = signedStruct.enabled;

        emit SetConfig(
            signedStruct.user,
            signedStruct.midnightId,
            signedStruct.blueId,
            signedStruct.start,
            signedStruct.end,
            signedStruct.incentiveAtStart,
            signedStruct.incentiveAtEnd,
            signedStruct.minRollableAssets,
            signedStruct.enabled
        );
    }

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
    ) external override {
        bytes32 midnightId = IdLib.toId(midnightMarket);
        bytes32 blueId = Id.unwrap(blueMarketParams.id());
        bytes32 configId =
            keccak256(abi.encode(midnightId, blueId, start, end, incentiveAtStart, incentiveAtEnd, minRollableAssets));
        require(isConfig[user][configId], NotConfigured());
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

        uint256 debtAssets = IMidnight(MIDNIGHT).debt(midnightId, user);
        require(assets >= minRollableAssets || debtAssets <= minRollableAssets, RollableAssetsTooLow());

        // Round in favor of the Midnight position.
        uint256 collateralAssets =
            IMidnight(MIDNIGHT).collateral(midnightId, user, collateralIndex).mulDivDown(assets, debtAssets);
        // Round against the roller.
        uint256 incentiveFactor = incentiveAtEnd >= incentiveAtStart
            ? incentiveAtStart
                + UtilsLib.mulDivDown(incentiveAtEnd - incentiveAtStart, block.timestamp - start, end - start)
            : incentiveAtStart
                - UtilsLib.mulDivUp(incentiveAtStart - incentiveAtEnd, block.timestamp - start, end - start);
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
