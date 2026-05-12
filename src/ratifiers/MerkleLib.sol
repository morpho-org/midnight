// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

/// @dev Helpers for verifying signed Merkle trees of offers.
library MerkleLib {
    error InvalidOfferTreeHeight();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height < 10) {
            if (height == 0) return 0x0e43d8df2f3684b785fa9fcc30e9fb1854aabdc3b41299c295e40719905aa409;
            if (height == 1) return 0x5d2cda016e26c76fc76abd14730b171e5728b985396fdd915f578684ebbe7c08;
            if (height == 2) return 0xefac405c5f69bfadf16128c7517214821f43ed43418cb105786797e775c82208;
            if (height == 3) return 0x31c93107b446078165ed61fdc00f9d9fcd4f3caaa1190a450d2ea6f5458eaccf;
            if (height == 4) return 0xe0dee184a8590b1f885af247ca09e36c68586dbffa6867fa9b3b59558beffc15;
            if (height == 5) return 0xd6e86cf62241738635bac0675446526dba2111139cd29cbe51540d1951f0f9d9;
            if (height == 6) return 0x60b0a7b9b8026fb0843b29674731a80da02604c07e87380acba1e834127c036d;
            if (height == 7) return 0xb57b5627fd51b740272bee7750d8a0f52856db5761767bbc90795d1166400f91;
            if (height == 8) return 0xd9ea3b8d089568ca3a3e0858ec120441ef7ac3714712f451d18de174961ac92f;
            return 0x7b1ceacb8b39729bf3887cec726d34a4b6944eb84eb8e9cdfe0d7070ad75ca30;
        }
        if (height == 10) return 0x56d6ab434a3896c1d1c814fe3e7c22fc7c1f9b9177a50f2f79e754bb2199cdb0;
        if (height == 11) return 0x93f78fd001e8bafca3563f60c2f0f17b7a4eae11cd7f2009af2488b318b32e30;
        if (height == 12) return 0x7f4b555dd8cdba4396e42215d878847ba64c29ea68d852161264ccd43008e2df;
        if (height == 13) return 0x3b3c022990f3110616cb95bee08380dee66e3a47a67d9c2c7ec1828102367957;
        if (height == 14) return 0x2519b2c8c6476345d46d5f543ee11f421886319e2d68f2df4ec54344393d402f;
        if (height == 15) return 0x342d2f85060d6c90578ac9783b38ba80e002837fc89448ae771ac246d4c68ce3;
        if (height == 16) return 0xe3ff3face5c6307122b29d3f23b7106ab79793236005007af9e94bbc4d9836a7;
        if (height == 17) return 0x9a955710808f486fc37d0607e120c223cc8b2029dab35c6ec7840ff9aea1ff52;
        if (height == 18) return 0x419a52abde7cb2ff4d4eeb2f65b93dc2e05a12ea6f7a9c379b0b25558c34741f;
        if (height == 19) return 0x9cf0a4c02fe1d55648b3c157e49872c82d1bc404e3c5359c02aba6cb0d934ddb;
        revert InvalidOfferTreeHeight();
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
}
