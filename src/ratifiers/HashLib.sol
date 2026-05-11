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
