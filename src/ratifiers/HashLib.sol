// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Obligation, CollateralParams} from "../interfaces/IMidnight.sol";

bytes constant COLLATERAL_PARAMS_TYPE = "CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)";
/// @dev keccak256(COLLATERAL_PARAMS_TYPE)
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0xaf44a88eb50ebdbbebd980e5a23045c44f61ece5f80ab708a1bbe8718102e6af;
bytes constant OBLIGATION_TYPE =
    "Obligation(address loanToken,CollateralParams[] collateralParams,uint256 maturity,uint256 rcfThreshold,address enterGate,address liquidatorGate)";
/// @dev keccak256(bytes.concat(OBLIGATION_TYPE, COLLATERAL_PARAMS_TYPE))
bytes32 constant OBLIGATION_TYPEHASH = 0xdcb3d766540d305590a1ee685cb2636a7271c1eea05949c19a23eb48c7492d24;
bytes constant OFFER_TYPE =
    "Offer(Obligation obligation,bool buy,address maker,uint256 start,uint256 expiry,uint256 tick,bytes32 group,bytes32 session,address callback,bytes callbackData,address receiverIfMakerIsSeller,address ratifier,bool reduceOnly,uint256 maxUnits,uint256 maxSellerAssets,uint256 maxBuyerAssets)";
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, OBLIGATION_TYPE))
bytes32 constant OFFER_TYPEHASH = 0xa75bd7b6468a41ab66f3aa9c068cf8ba48ebfb736e548c3fda0ef0f9e18857a5;

library HashLib {
    /// @dev Computes the EIP-712 hash struct of a CollateralParams.
    function hashCollateralParams(CollateralParams memory collateralParams) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                COLLATERAL_PARAMS_TYPEHASH,
                collateralParams.token,
                collateralParams.lltv,
                collateralParams.maxLif,
                collateralParams.oracle
            )
        );
    }

    /// @dev Computes the EIP-712 hash struct of an Obligation.
    function hashObligation(Obligation memory obligation) internal pure returns (bytes32) {
        bytes32[] memory collateralParamsHashes = new bytes32[](obligation.collateralParams.length);
        for (uint256 i = 0; i < obligation.collateralParams.length; i++) {
            collateralParamsHashes[i] = hashCollateralParams(obligation.collateralParams[i]);
        }

        bytes32 collateralParamsHash;
        // same as keccak256(abi.encodePacked(collateralParamsHashes));
        assembly ("memory-safe") {
            collateralParamsHash := keccak256(
                add(collateralParamsHashes, 0x20),
                mul(mload(collateralParamsHashes), 0x20)
            )
        }

        return keccak256(
            abi.encode(
                OBLIGATION_TYPEHASH,
                obligation.loanToken,
                collateralParamsHash,
                obligation.maturity,
                obligation.rcfThreshold,
                obligation.enterGate,
                obligation.liquidatorGate
            )
        );
    }

    /// @dev Computes the EIP-712 hash struct of an Offer.
    /// @dev Same as keccak256(abi.encode(OFFER_TYPEHASH, ...));
    function hashOffer(Offer memory offer) internal pure returns (bytes32) {
        bytes32[17] memory w;
        w[0] = OFFER_TYPEHASH;
        w[1] = hashObligation(offer.obligation);
        w[2] = bytes32(uint256(offer.buy ? 1 : 0));
        w[3] = bytes32(uint256(uint160(offer.maker)));
        w[4] = bytes32(offer.start);
        w[5] = bytes32(offer.expiry);
        w[6] = bytes32(offer.tick);
        w[7] = offer.group;
        w[8] = offer.session;
        w[9] = bytes32(uint256(uint160(offer.callback)));
        w[10] = keccak256(offer.callbackData);
        w[11] = bytes32(uint256(uint160(offer.receiverIfMakerIsSeller)));
        w[12] = bytes32(uint256(uint160(offer.ratifier)));
        w[13] = bytes32(uint256(offer.reduceOnly ? 1 : 0));
        w[14] = bytes32(offer.maxUnits);
        w[15] = bytes32(offer.maxSellerAssets);
        w[16] = bytes32(offer.maxBuyerAssets);
        bytes32 result;
        assembly ("memory-safe") {
            result := keccak256(w, 0x220)
        }
        return result;
    }
}
