// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Market, CollateralParams} from "../../interfaces/IMidnight.sol";

/// @dev keccak256("CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)").
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0xaf44a88eb50ebdbbebd980e5a23045c44f61ece5f80ab708a1bbe8718102e6af;
/// @dev keccak256(bytes.concat(MARKET_TYPE, COLLATERAL_PARAMS_TYPE)).
bytes32 constant MARKET_TYPEHASH = 0x3fff861e0066633dc719c2511eb3c771b1517a7f8fad53b0bef7edd4a94d398d;
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant OFFER_TYPEHASH = 0x2d9b2c48e9f7b87e10d277cc9eb2abc4a9cd2ec3451bd3990be472fe4ac78137;

library HashLib {
    error LeafIndexOutOfRange();
    error TreeTooHigh();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("OfferTree(Offer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// MARKET_TYPE, OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0xb7013fa5a999e5458627829111d031bbfa33e47889dca4e3514af04af509f09f;
            if (height == 1) return 0xf815228253919597971ee6a6ca2adf2c3d8fc6296c7b86836ef214bd443daa58;
            if (height == 2) return 0x893585f92cecb9f687cb75f92a57a6fc1754d8e5dad457ae1788158b26431712;
            if (height == 3) return 0x86a3d14f6eb5735e5b94524e19d4c3d93ac15ac07ff41cc0a56ac928c6196b75;
            if (height == 4) return 0xab8a93d114b72108b54341384805d18d28645e84d0c529c2c51953458047059f;
            if (height == 5) return 0xb17a31924a5fc4d78bd61198e129de2fbdb46b962ed5c31ede6e96387491219f;
            if (height == 6) return 0xbde56d2c07e3653be3d1f612a6f80ee60b75b327b5f2de0ebee98edea7b691db;
            if (height == 7) return 0x6b2caaf1294590779ca6a569e9568e6980c547581cffff04f04a010e4bea0181;
            if (height == 8) return 0x73b960155d0c9f339157d36610ccd76774a8dcd8a613f2127880e6d1f3590c5a;
            if (height == 9) return 0xcc0480fc3e9396c4ecc52012adf81e481e0d1edecc3933d3b23e8150d26fd8e3;
            return 0xada0eb530ea41beaf0af9972929d04e52040aaec090096b0598c39a34167bab6;
        } else {
            if (height == 11) return 0x81fa0e3280af655d1107469f0cd022c73f57a8b97b0ac19757162e4ccf21b6da;
            if (height == 12) return 0x16f061da90a7f30a2af2f5ccc13be13a022de02a32aee285be67085861b8b913;
            if (height == 13) return 0x7195f81e3204ac6040f29531f347d18dbe10552cd4618aba0793abb71cc6c19c;
            if (height == 14) return 0x48659bfedd6ab7bbdaa4a0fb2491b9150191c54f84cdc6da5d2a4baea9f2722f;
            if (height == 15) return 0x3f18ed4b2ad3720c79905889f1900cb770043edab868f1afa0d4cca5b7623773;
            if (height == 16) return 0x3f939e01857b0725e963c412a35e5ee75cbc8c51d40cc5b33c11a4ef275b0086;
            if (height == 17) return 0x990e2f81f815d7e02dc7cd5bc6aa2ea6631372ce9563a586dc60807107a7320c;
            if (height == 18) return 0xf567d558ad0daa6e76e75e5bcba9d858ffcc43c1e48a98b07ce7665f41003158;
            if (height == 19) return 0x957d376d258c67c3c69b7a67ac562821c7a2c5e9c189e19e8a041ba5e4a2e223;
            if (height == 20) return 0x72e1d8247b3df82dfe2c47a385bba604682f719edf060edccd3a3e5c7e402849;
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
                market.initialChainId,
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
