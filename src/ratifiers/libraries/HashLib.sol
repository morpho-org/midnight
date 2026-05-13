// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Obligation, CollateralParams} from "../../interfaces/IMidnight.sol";

bytes constant COLLATERAL_PARAMS_TYPE = "CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)";
/// @dev keccak256(COLLATERAL_PARAMS_TYPE)
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0xaf44a88eb50ebdbbebd980e5a23045c44f61ece5f80ab708a1bbe8718102e6af;
bytes constant OBLIGATION_TYPE =
    "Obligation(address loanToken,CollateralParams[] collateralParams,uint256 maturity,uint256 rcfThreshold,address enterGate,address liquidatorGate)";
/// @dev keccak256(bytes.concat(OBLIGATION_TYPE, COLLATERAL_PARAMS_TYPE))
bytes32 constant OBLIGATION_TYPEHASH = 0xdcb3d766540d305590a1ee685cb2636a7271c1eea05949c19a23eb48c7492d24;
bytes constant OFFER_TYPE =
    "Offer(Obligation obligation,bool buy,address maker,uint256 start,uint256 expiry,uint256 tick,bytes32 group,address callback,bytes callbackData,address receiverIfMakerIsSeller,address ratifier,bool reduceOnly,uint256 maxUnits,uint256 maxAssets)";
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, OBLIGATION_TYPE))
bytes32 constant OFFER_TYPEHASH = 0xdf99c78ec0578533b0e52d329a9866adb5ef6bae6a0c56f9bb562ba6d9be867f;

library HashLib {
    error TreeTooHigh();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("OfferTree(Offer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// OBLIGATION_TYPE, OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0x9a4cffa064818006f9fa53857eafbd9974c971f009276be3fd30481edb617f49;
            if (height == 1) return 0x73e25e0ecda983be4e607052c9c61b1f73c5812c7963412e271ba99e98f38c7c;
            if (height == 2) return 0x9172b36c68635815d03f222ce2193bc103d476c9f2c84dedb041304ae7c22f75;
            if (height == 3) return 0xec6af766c7d762b2855f250b9f13ded677c04c8d69c43f137072d241d2a489ae;
            if (height == 4) return 0x073e69543318e08cf57881744e4374416351f0150b5d84a012da36fe123d80d0;
            if (height == 5) return 0x456356eca104d2cf05e643ef7fd0e6bb65a1a5721159fc458d9804f1d40c770c;
            if (height == 6) return 0x43a6840fbae6a9098ca657734227a6626feeb331dbefe5a8621ffcea16fbfee4;
            if (height == 7) return 0x426ba4f3e501aeff3b12f2620e1b7278bd27254693b9d1be525e76d90ad81983;
            if (height == 8) return 0x8c83e4332d4c4582e00472571210879c28961c85af403f7ca8cf1c588ed73fea;
            if (height == 9) return 0x51e09d5a4a99b2f34b074afaf10f6090ee01d0d8dc881b2a33e0862efdea4389;
            return 0x2bbf39e344c1df3e8d099b61e9fadcfff00366ed08390402298e7aff84f40b01;
        } else {
            if (height == 11) return 0xe6e20c789f3afce3a3fe9de56059bedcfca0b6104ffbfd752491e49691267cdb;
            if (height == 12) return 0x8ce2628ddc927bcfc3466ced668b48102af1bb61ff7f42c3b58c78cbd8f5fd01;
            if (height == 13) return 0xe7f97c22e30d8b9e693dd81bf4f5794ef72413105d9b0858c12affcf16300523;
            if (height == 14) return 0x4fe3f1f3a4921a4b2268ea7a7077dc7e95256b5b4e75ce221e94cf006263516c;
            if (height == 15) return 0x0407c3a3ad36093fe23beb83a4b6e719a138d03fc7d36a85b10efc76713a1293;
            if (height == 16) return 0xa1e429b3cef45d25743c2abee55b9a2dd7ff33512791e83ed8f45039419d5da3;
            if (height == 17) return 0xa33a8f9b581ff5d305b36b96ba23dc5d3337288af80f8a3d60ba9b6ac3dd347c;
            if (height == 18) return 0x2003b976fb1f6e95af69350f4b4244bcada74db4164041a7b3808a91206d334e;
            if (height == 19) return 0x192d0bfd097f77eb5ad08f728288a1e7525ecfbe73bfdad7b311a21d8c4134ae;
            if (height == 20) return 0xfbc96454b1a9e6406df6a70ee6acecc03f3b0a20a4253abddcbb695175b3bc11;
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
    function hashOffer(Offer memory offer) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OFFER_TYPEHASH,
                hashObligation(offer.obligation),
                offer.buy,
                offer.maker,
                offer.start,
                offer.expiry,
                offer.tick,
                offer.group,
                offer.callback,
                keccak256(offer.callbackData),
                offer.receiverIfMakerIsSeller,
                offer.ratifier,
                offer.reduceOnly,
                offer.maxUnits,
                offer.maxAssets
            )
        );
    }
}
