// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Market, CollateralParams} from "../../interfaces/IMidnight.sol";

/// @dev keccak256("CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)").
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0xaf44a88eb50ebdbbebd980e5a23045c44f61ece5f80ab708a1bbe8718102e6af;
/// @dev keccak256(bytes.concat(MARKET_TYPE, COLLATERAL_PARAMS_TYPE)).
bytes32 constant MARKET_TYPEHASH = 0xc66c045aa2394a02e2976962976ec58c79108ae7fbb1ecc974c9724678b56264;
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant OFFER_TYPEHASH = 0x5e7c764a0f2411d16dd65139c973cbe0fe976b6d0736823e17aef319f652e7f8;

library HashLib {
    error LeafIndexOutOfRange();
    error TreeTooHigh();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("OfferTree(Offer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// MARKET_TYPE, OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0x04931ea05149e935551af887e04668a4235aa7fefe5a1307699fc36de5da3604;
            if (height == 1) return 0x636eec88d23afdd7c5ecd3689cddd4a578f3640022a4f4b36532b1bb873870d9;
            if (height == 2) return 0xb3b200d8a87156dd298add6829190724360e913ea2a544cf8770a83b1a85b68e;
            if (height == 3) return 0x9959f9ee7df42c7c3a42ae48edb3544cb9672653eb4c9ad5190aa9ac194e13cc;
            if (height == 4) return 0x859439b1a679d2b8d78d092af16a3e3abd30ccae9d29e12183c61dbd89069798;
            if (height == 5) return 0x3b62f568d54c69f46baa3db29d9d16daa670a421eca545015e2c4d6ac5e2ab4b;
            if (height == 6) return 0x06b027b3e518caa75c38007c1e4cffc92d314d528eb7ed63b28f6cbb250d6221;
            if (height == 7) return 0x1948d59b3835088b65d9f7048f26cfcf508f9a750de32e7830b6f99c8915905a;
            if (height == 8) return 0xfb12ec1a894c5cc36be99898bcc4c23d45713b8920d21ddf94ba0053fec835b4;
            if (height == 9) return 0xee136fb578b4eea50b5929361278f0a09f97371d5c44ebb73b07785150f3c202;
            return 0xdbd2c72ce0b8a438efba0500c50090d842804420fa9eb5819a265105ccf446d4;
        } else {
            if (height == 11) return 0x8201cbae421a17b9d8116ce28ecd13378b22d0257e9daca65ea354dc7b852e0a;
            if (height == 12) return 0xb76e7eedf6cb4dfd2a913d292be9bbcdcdf6bc457e789306cc23a6917faca3d2;
            if (height == 13) return 0x911f1aca18bfbc4e142c04b2020d972507d4b9d6b2fbef339bc48d33a438be9e;
            if (height == 14) return 0xf8b8028014cfa85c41a0b5af6dd4d5e6c7236dab5886ee4f21e845ec4205443d;
            if (height == 15) return 0xd517d3bc505b0209f539cf985e6252f0e57975ec5c8e3a93d97366f39c8cbbc5;
            if (height == 16) return 0x35940ca810d4b02086a4d695dfaf04195c5a0fcb776e97c1349a8a0472b7bec8;
            if (height == 17) return 0x44c0e3ddcf369c808911a5c78a3d7e87fa115a23cc40147b5fc40064c5560213;
            if (height == 18) return 0x032fe7574172aadd1fb6c40e9deacfec41a48e2fc8de3574c67331c10e7b3a1f;
            if (height == 19) return 0x3f80439b44bef469ff2390bdf0fd5469db472bb6748c6de9e5e2cd86d602c301;
            if (height == 20) return 0x61068a1b8ffb6dd774e8a9634cb46a7a214dd84189e255072577c8541c543fd4;
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
