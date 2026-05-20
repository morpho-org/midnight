// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Market, CollateralParams} from "../../interfaces/IMidnight.sol";

/// @dev keccak256("CollateralParams(address token,uint256 lltv,uint256 maxLif,address oracle)").
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0xaf44a88eb50ebdbbebd980e5a23045c44f61ece5f80ab708a1bbe8718102e6af;
/// @dev keccak256(bytes.concat(MARKET_TYPE, COLLATERAL_PARAMS_TYPE)).
bytes32 constant MARKET_TYPEHASH = 0x358117e98511cc3df97175dca58053b06675b43ad090b0553f8a1eff008b6e2e;
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant OFFER_TYPEHASH = 0x980a4cfc9766df84667f316d76e10cefc8caf04fb4cd4a9fca00a8e7b34f619c;

library HashLib {
    error LeafIndexOutOfRange();
    error TreeTooHigh();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("OfferTree(Offer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// MARKET_TYPE, OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0x2b9ee710e1977dfc5778fe18c905ccc1d9e144baf3ba83be732d4da65ecb73e3;
            if (height == 1) return 0x3cc16189b92a85898f1d5c6e87282c8ded7c1c93b2323d5e85ae10c5f4b2b220;
            if (height == 2) return 0x6de37d3e570afa293a8107d4b6b1d9547616c04f42164d009c89194787b2ffa6;
            if (height == 3) return 0xba3ea2ddfbf40a906fcd1b9506dbd344c062e8dcba8b5c902ceb13339f45a358;
            if (height == 4) return 0xe5faa865e93bc1b7b8fdf91980f54682d649683b014edd6c54b642f5a0c96977;
            if (height == 5) return 0xeda50f61dd2a827c6ff9fbfcd54335628dcaa78aaa4f2d118c60886219cdce2b;
            if (height == 6) return 0x54e2c9cc40cdc0e9ad530cf2be298f952f57af2b18b02f88274a9bbab359d23a;
            if (height == 7) return 0xc9d81859d60d6b21c688f4be93ca83e3be222728bb156ef5f4cf497f879f1e29;
            if (height == 8) return 0xd59b0c4544e0c60c8611eab0aaa402575f14ee784d22289c5d57f48c422a62d6;
            if (height == 9) return 0xccad21701f34f08bb8398a3dbc77e20e4c9c424930f3a8b31485bf059e2bdb20;
            return 0x8a42dfb49807647bfc49c906aef322aa0239d40e4cb675761e141bc7bfa530da;
        } else {
            if (height == 11) return 0x2adc0d948b2e3ecb642661590d2eec36d4e71e9acf382deb6574371800caf198;
            if (height == 12) return 0xf5845dfaed016de272342f346346a49d4b1694f622144d420558a38e46ac9dad;
            if (height == 13) return 0x3d7df854e6294bf433b64bbb8d0a82fa875a87b45b0016db27fc5752e54126ad;
            if (height == 14) return 0x72a991a101708716ff427c524404ab44f4d4d1f4e7e76c0ae8b967222164b348;
            if (height == 15) return 0x762c88fc52cf78a54401d247790f1bdb619d51d3458d1415c20d1422197cecc4;
            if (height == 16) return 0x8ede2209e94c8d5f8379d733dc8712b71a3888c1c4b70f3d6b22285f70bf4286;
            if (height == 17) return 0x425b18f07b3ac2f641977d2c294590565dd40b5d8414610568dca64628399975;
            if (height == 18) return 0x7e7d98718c0180e882e5963b9bd49810096912c273dfa38d8afdd6d39fde86ec;
            if (height == 19) return 0x8d35d491a29d846489e19688efff3c4cc7dbd54458058d49b30294074539f0b9;
            if (height == 20) return 0x824e385eea1953bcbc783bf900b18aa6fba129b6908765e986cf0968b491ec4f;
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
