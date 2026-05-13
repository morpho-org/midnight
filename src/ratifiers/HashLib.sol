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
    "Offer(Obligation obligation,bool buy,address maker,uint256 start,uint256 expiry,uint256 tick,bytes32 group,bytes32 session,address callback,bytes callbackData,address receiverIfMakerIsSeller,address ratifier,bool reduceOnly,uint256 maxUnits,uint256 maxAssets)";
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, OBLIGATION_TYPE))
bytes32 constant OFFER_TYPEHASH = 0x832d2325d9fdecb4919fae592db91c04ed32e757cf419102a9ca1b54187a02aa;

library HashLib {
    error TreeTooHigh();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("OfferTree(Offer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// OBLIGATION_TYPE, OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height < 11) {
            if (height == 0) return 0xe44a06d7beccd42078013099c75f6bf15bbf7011b32f0fac5f0d1be11209fb45;
            if (height == 1) return 0xe76957cbe055f833a3535c27c910d8b3ff551c57122cd7c144664dcaf6ef57c2;
            if (height == 2) return 0x8ed636f96d015ec0b37331755bd1ed810b518651d1f608ef0da8faf8a716a9fa;
            if (height == 3) return 0xed435d712423199e157e3b5a09dae057b80f4e24c66506fab90a532a281f119b;
            if (height == 4) return 0xc0be3e3e3db20135f4e4b0e0ec303b2370bff3a6c6f1694e590688679d3c791d;
            if (height == 5) return 0xa11a82bad74d349c4815e64b3d1c0e8b67996a416bed7de5be2a3f99c713f0ea;
            if (height == 6) return 0x26b9fced7071170acdd2cccb33b167efab84a6e642da76eb114c28bfa65b64fa;
            if (height == 7) return 0x8fe59ac3e9ed3d2b996863d15a70fc04e25d57b0c38a84a106f382d650a852d7;
            if (height == 8) return 0xb5a57691ae822b37e31d9777d494a7c87678280f896cbad814b660390eea6b61;
            if (height == 9) return 0xd87a4d4c8046ebabe9b990871cb18534f7f62534e5659e739c679aa6378d5519;
            return 0x52d7e6cdfd06ffa64fec4914dd59d23b2a18610350763964ffe997412517b37a;
        } else {
            if (height == 11) return 0xfa83a2c65fb1461f15e882933fe76b1bdc109593e0290fc9e7b8b1cf563ab45b;
            if (height == 12) return 0x48c3385bb136122d66812803a4900c7fe06ea36fcd4b1723a73d83e7ca0cc741;
            if (height == 13) return 0x20e338378ffdffb282b5d15c84729a501620e94aee44ce9f79b51226dad53da3;
            if (height == 14) return 0x1245eebd3b0c0d2eb646c2774d01ac8e25e5e15546e0c541da165f3fd323b4ea;
            if (height == 15) return 0xdbe18915d349eb57a97c0c27074f78cdd7ef74c4bbb462f3c2af5f6309c7d333;
            if (height == 16) return 0xfe68c4beb45b8b211183073f7ba722b88b74c83dd8106a32b99a67223773c1a3;
            if (height == 17) return 0xf3d480585999f714d3c14b21dc8778a5b482ab9de408b58d1d9b2eda9e72c728;
            if (height == 18) return 0x5ca45d9e6845331c5349cd07435d2a3f2b9fe342794a628f12067aca895432fe;
            if (height == 19) return 0x27ab2cec644494459bf6cfbde6c271fdc8b089d0552aa014bef0c44965cbfa71;
            if (height == 20) return 0xdb06b6765eb9ed46556b2d149c00a81e61a0f019925b5948d368a37c841ef7f9;
            revert TreeTooHigh();
        }
    }

    /// @dev Returns hash(... hash(leafHash, proof[0]), ..., proof[n]) == root.
    /// @dev Hash sorts the inputs lexicographically.
    function isLeaf(bytes32 root, bytes32 leafHash, bytes32[] memory proof) internal pure returns (bool) {
        bytes32 currentHash = leafHash;
        for (uint256 i = 0; i < proof.length; i++) {
            currentHash = commutativeHash(currentHash, proof[i]);
        }
        return currentHash == root;
    }

    /// @dev Returns the keccak256 hash of the sorted concatenation of a and b.
    function commutativeHash(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        if (a > b) (a, b) = (b, a);
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

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
        bytes32[16] memory w;
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
        w[15] = bytes32(offer.maxAssets);
        bytes32 result;
        assembly ("memory-safe") {
            result := keccak256(w, 0x200)
        }
        return result;
    }
}
