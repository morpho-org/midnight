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
    "Offer(Obligation obligation,bool buy,address maker,uint256 start,uint256 expiry,uint256 tick,bytes32 group,bytes32 session,address callback,bytes callbackData,address receiverIfMakerIsSeller,address ratifier,bool reduceOnly,uint128 maxUnits,uint128 maxAssets)";
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, OBLIGATION_TYPE))
bytes32 constant OFFER_TYPEHASH = 0x0d3b90ced1b7c16a67ad780a54e7bef8c3a7c29133ed3f7ff5b5b202162ec990;

library HashLib {
    error TreeTooHigh();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("OfferTree(Offer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// OBLIGATION_TYPE, OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height < 11) {
            if (height == 0) return 0x61679248b870a420995ea12e35cadfc91943374dbdbcc9ee765b87f80d9f97b9;
            if (height == 1) return 0xfb0162c105acf6c8ae16b948943a153ca493de3285b5cb476738e975241ff678;
            if (height == 2) return 0xbb67a36581a94f5d31e43f9cc92f8e1e59d348b7b708a4ababe691c3484cbe8b;
            if (height == 3) return 0xe31c5dbfd56bfd78e4aa9523efedf382ce358ea8dd6601cbde12a52b0ce6a61f;
            if (height == 4) return 0x86296740b8ca62a6e9bfa24605987f3a2e4fc715ccdd8665c7047c4ea9ce2e95;
            if (height == 5) return 0x506f3dcba431c68ad663cd015355d6d3ab781cbfcb5891ceb0291f76eb9c8bb9;
            if (height == 6) return 0xa76fb05523f3c4ea3d6c6745b80ddb9f3ec63294799436dfc88d309b5acd8d7c;
            if (height == 7) return 0xa231a934d74c339b2e6db0fef6f84f6a29870cf2665adb3039e1fec0afa8968e;
            if (height == 8) return 0x0e02866958bc6b473045d4a3ebf6502fe1b63e9d7a190febdf778b6ecf95de23;
            if (height == 9) return 0x8bb3658c3a1cd24844751e12ae00a989dce1d538063844784f31c158744c577e;
            return 0x4056275b824a2d59cb638ff6f849ea6980647aff86b98b0a9b09ace7433449ca;
        } else {
            if (height == 11) return 0x5883ce51fd697b5a5153a343229abb98b2d1954aa3e197ab03f5f95e934d472f;
            if (height == 12) return 0xc968de119bbaad1b579cc1cbb21be69567e9f34e19780f3e68fcbb3b87e6cc1c;
            if (height == 13) return 0x88b1102d550a65b19687435008b803188447e17853881851d494726d860f2f67;
            if (height == 14) return 0xe1c4ed9377b6182bfa931386c150ce3fd52d49c72ed8696b3ca5e45de75e603f;
            if (height == 15) return 0xfbd2b389260adf38f8b8056c431d537858e9644d2acf9b64e1d1d1d3771b5fc8;
            if (height == 16) return 0x063d4f0e8b648a0b427b64d587a52bdb8b09f413f2764349a82a4b85840d28b0;
            if (height == 17) return 0x3b7f438aae35f315aa2f874230590827a95d8586a9051de52f2dd2b71492d3dd;
            if (height == 18) return 0x78fdbdea27f04eaba7573de1ad43c1a53ff752656ae0ccd887fc4d6646a86660;
            if (height == 19) return 0x12db760fae7dd69b552da24f2265b18ed82def880efc05eeef0af1af71aae573;
            if (height == 20) return 0x0b076f66b929e423728aeccddf8268bfb230cd1b62b7da469f8c1a5049b5fc38;
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
        w[14] = bytes32(uint256(offer.maxUnits));
        w[15] = bytes32(uint256(offer.maxAssets));
        bytes32 result;
        assembly ("memory-safe") {
            result := keccak256(w, 0x200)
        }
        return result;
    }
}
