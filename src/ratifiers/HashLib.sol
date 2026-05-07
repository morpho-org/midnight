// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Obligation, CollateralParams} from "../interfaces/IMidnight.sol";
import {COLLATERAL_PARAMS_TYPEHASH, OBLIGATION_TYPEHASH, OFFER_TYPEHASH} from "../libraries/ConstantsLib.sol";

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

        return keccak256(
            abi.encode(
                OBLIGATION_TYPEHASH,
                obligation.loanToken,
                keccak256(abi.encodePacked(collateralParamsHashes)),
                obligation.maturity,
                obligation.rcfThreshold,
                obligation.enterGate,
                obligation.liquidatorGate
            )
        );
    }

    /// @dev Computes the EIP-712 hash struct of an Offer.
    /// @dev Split into two abi.encodes to avoid stack-too-deep without optimizer (Certora compiles in that mode).
    function hashOffer(Offer memory offer) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                abi.encode(
                    OFFER_TYPEHASH,
                    hashObligation(offer.obligation),
                    offer.buy,
                    offer.maker,
                    offer.start,
                    offer.expiry,
                    offer.tick,
                    offer.group,
                    offer.session
                ),
                abi.encode(
                    offer.callback,
                    keccak256(offer.callbackData),
                    offer.receiverIfMakerIsSeller,
                    offer.ratifier,
                    offer.reduceOnly,
                    offer.maxUnits,
                    offer.maxSellerAssets,
                    offer.maxBuyerAssets
                )
            )
        );
    }
}
