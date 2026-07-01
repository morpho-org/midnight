// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Market, CollateralParams} from "../../interfaces/IMidnight.sol";

/// @dev keccak256("CollateralParams(address token,uint256 lltv,uint256 liquidationCursor,address oracle)").
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0x39ed3f928d24fd00574b1a02aba9c2483abcf5d9a3a366118c9a5aa29885b841;
/// @dev keccak256(bytes.concat(MARKET_TYPE, COLLATERAL_PARAMS_TYPE)).
bytes32 constant MARKET_TYPEHASH = 0x510b3862f3816a109c9340b76972e8a30984246be06e034ae12ed2934220391a;
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant OFFER_TYPEHASH = 0x9905214264a9fb7b6cc1b0e33db7a04687c6e4185a84755d29914314aa9d8906;

library HashLib {
    error LeafIndexOutOfRange();
    error TreeTooHigh();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("OfferTree(Offer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// MARKET_TYPE, OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0x270da1ebafc0f24637af3612fb8c3a1d828fcb56d3637c24e86dd006b12ca7f9;
            if (height == 1) return 0x828b9cdf8326a1cf234328e4d5229546a98fb72ef73624f5b6b31538e555b96c;
            if (height == 2) return 0xfcb7a3ca4094246b8185620c4cf025c93032b6f0384805aa3f22afe04290e982;
            if (height == 3) return 0xcc97cb1955496a5269b5a7afca62ba694edcab26ba838a1adbd257931249de92;
            if (height == 4) return 0xda3feb08db360ad9e09540132ff04d2b6a596fdaa4747892217aaa4c7c9bcc31;
            if (height == 5) return 0x15bd6e2aa1a7a61614187ac16d2cbf8610c8f2f3c3d9eaa380ae7a501ee3cf06;
            if (height == 6) return 0xb726cb7fab1a24c28213cbd482fa5a301f127fb25feb01da341919983a72711a;
            if (height == 7) return 0xcea9cd557c6f821868ea287304199d0e0554af630bfa8fe36c64eb3bbacca418;
            if (height == 8) return 0xf7dbde8234e8e345cec8fc0a8ac5909ee336b214882751ecd51e7b37df4f6cdd;
            if (height == 9) return 0x5400a5d43d39e6bfe910af8cb84ac77bf501d310413769dffd62ccecda8b00c6;
            return 0x0754209b60d99d0822b3ecd5a970f9db09df9c8998a8441e24b81f06d6c76fee;
        } else {
            if (height == 11) return 0xf5d561d88647c3b38ed6636709d3166819fc66f8ed52a0daf4ae186387b4646c;
            if (height == 12) return 0x5801c07a6c7df039ce00a7a2b8bd92aa1cf333c30b0bc3d78768590b6063d09e;
            if (height == 13) return 0xc9da7190eaf4b14c7cb1c14f9898256c0adb6b1dc303afe79594dea64fe199c0;
            if (height == 14) return 0xa47534c85ac57c583568465d40fd46683d2d558d8129fe1aca01e93023afca92;
            if (height == 15) return 0xb1e841691fb54f4ef85e2ed9de45d610e57f49e1e6eb2510ceead16e447dd519;
            if (height == 16) return 0x4fa4f16f09f0c36c7670449a4032073380d28a60071e12ee8874bb3e5a8318fc;
            if (height == 17) return 0x817bbaac8bb863670f488b454cdd5d0990d9d81871a68e9df381c3c13d3f2ba2;
            if (height == 18) return 0xc447f06079bddf4b011523c4bce119e9e90fdf937de4ee88f48010406560e9c1;
            if (height == 19) return 0x1608d5eb56943c667c34b413f9f8a1c24a84ddfe1301a9c25487e638de1f5822;
            if (height == 20) return 0x3a677100d2e855c24a62d1e9c365bff90d02287f066a07064843ca1ee70ea113;
            revert TreeTooHigh();
        }
    }

    /// @dev Verifies a Merkle proof using the leaf index to determine the left/right position of each sibling.
    /// @dev Works for offer-tree heights up to 256, the bit-width of leafIndex.
    function isLeaf(bytes32 root, bytes32 leafHash, uint256 leafIndex, bytes32[] memory proof)
        internal
        pure
        returns (bool)
    {
        require(leafIndex >> proof.length == 0, LeafIndexOutOfRange());
        bytes32 currentHash = leafHash;
        for (uint256 i = 0; i < proof.length; i++) {
            currentHash = (leafIndex >> i) & 1 == 0 ? hashNode(currentHash, proof[i]) : hashNode(proof[i], currentHash);
        }
        return currentHash == root;
    }

    /// @dev Returns the keccak256 hash of the concatenation of left and right.
    function hashNode(bytes32 left, bytes32 right) internal pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, left)
            mstore(0x20, right)
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
                collateralParams.liquidationCursor,
                collateralParams.oracle
            )
        );
    }

    /// @dev Computes the EIP-712 hash struct of a Market.
    function hashMarket(Market memory market) internal pure returns (bytes32) {
        bytes32[] memory collateralParamsHashes = new bytes32[](market.collateralParams.length);
        for (uint256 i = 0; i < market.collateralParams.length; i++) {
            collateralParamsHashes[i] = hashCollateralParams(market.collateralParams[i]);
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
                MARKET_TYPEHASH,
                market.chainId,
                market.midnight,
                market.loanToken,
                collateralParamsHash,
                market.maturity,
                market.rcfThreshold,
                market.enterGate,
                market.liquidatorGate
            )
        );
    }

    /// @dev Computes the EIP-712 hash struct of an Offer.
    function hashOffer(Offer memory offer) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OFFER_TYPEHASH,
                hashMarket(offer.market),
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
                offer.maxAssets,
                offer.continuousFeeCap
            )
        );
    }
}
