// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Market, CollateralParams} from "../../interfaces/IMidnight.sol";

bytes constant COLLATERAL_PARAMS_TYPE = "CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)";
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = keccak256(COLLATERAL_PARAMS_TYPE);
bytes constant MARKET_TYPE =
    "Market(address loanToken,CollateralParams[] collateralParams,uint256 maturity,uint256 rcfThreshold,address enterGate,address liquidatorGate)";
bytes32 constant MARKET_TYPEHASH = keccak256(bytes.concat(MARKET_TYPE, COLLATERAL_PARAMS_TYPE));
bytes constant OFFER_TYPE =
    "Offer(Market market,bool buy,address maker,uint256 start,uint256 expiry,uint256 tick,bytes32 group,address callback,bytes callbackData,address receiverIfMakerIsSeller,address ratifier,bool reduceOnly,uint256 maxUnits,uint256 maxAssets)";
bytes32 constant OFFER_TYPEHASH = keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE));

// forgefmt: disable-start
bytes32 constant OFFER_TREE_TYPEHASH_0  = keccak256(bytes.concat("OfferTree(Offer offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_1  = keccak256(bytes.concat("OfferTree(Offer[2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_2  = keccak256(bytes.concat("OfferTree(Offer[2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_3  = keccak256(bytes.concat("OfferTree(Offer[2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_4  = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_5  = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_6  = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_7  = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_8  = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_9  = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_10 = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_11 = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_12 = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_13 = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_14 = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2][2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_15 = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2][2][2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_16 = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_17 = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_18 = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_19 = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
bytes32 constant OFFER_TREE_TYPEHASH_20 = keccak256(bytes.concat("OfferTree(Offer[2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2][2] offerTree)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE, OFFER_TYPE));
// forgefmt: disable-end

library HashLib {
    error LeafIndexOutOfRange();
    error TreeTooHigh();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("OfferTree(Offer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// MARKET_TYPE, OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return OFFER_TREE_TYPEHASH_0;
            if (height == 1) return OFFER_TREE_TYPEHASH_1;
            if (height == 2) return OFFER_TREE_TYPEHASH_2;
            if (height == 3) return OFFER_TREE_TYPEHASH_3;
            if (height == 4) return OFFER_TREE_TYPEHASH_4;
            if (height == 5) return OFFER_TREE_TYPEHASH_5;
            if (height == 6) return OFFER_TREE_TYPEHASH_6;
            if (height == 7) return OFFER_TREE_TYPEHASH_7;
            if (height == 8) return OFFER_TREE_TYPEHASH_8;
            if (height == 9) return OFFER_TREE_TYPEHASH_9;
            return OFFER_TREE_TYPEHASH_10;
        } else {
            if (height == 11) return OFFER_TREE_TYPEHASH_11;
            if (height == 12) return OFFER_TREE_TYPEHASH_12;
            if (height == 13) return OFFER_TREE_TYPEHASH_13;
            if (height == 14) return OFFER_TREE_TYPEHASH_14;
            if (height == 15) return OFFER_TREE_TYPEHASH_15;
            if (height == 16) return OFFER_TREE_TYPEHASH_16;
            if (height == 17) return OFFER_TREE_TYPEHASH_17;
            if (height == 18) return OFFER_TREE_TYPEHASH_18;
            if (height == 19) return OFFER_TREE_TYPEHASH_19;
            if (height == 20) return OFFER_TREE_TYPEHASH_20;
            revert TreeTooHigh();
        }
    }

    /// @dev Verifies a Merkle proof using the leaf index to determine the left/right position of each sibling.
    /// @dev Works for offer-tree heights up to 256, the bit-width of leafIndex. In practice the height is capped at 20
    /// by offerTreeTypeHash.
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
                collateralParams.maxLif,
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
                offer.maxAssets
            )
        );
    }
}
