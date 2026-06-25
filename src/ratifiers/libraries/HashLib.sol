// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Market, CollateralParams} from "../../interfaces/IMidnight.sol";

/// @dev keccak256("CollateralParams(address token,uint256 lltv,uint256 liquidationCursor,address oracle)").
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0x39ed3f928d24fd00574b1a02aba9c2483abcf5d9a3a366118c9a5aa29885b841;
/// @dev keccak256(bytes.concat(MARKET_TYPE, COLLATERAL_PARAMS_TYPE)).
bytes32 constant MARKET_TYPEHASH = 0x510b3862f3816a109c9340b76972e8a30984246be06e034ae12ed2934220391a;
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant OFFER_TYPEHASH = 0xa316348449d1749c733fbf0befac14d04d6ed14ea8993956f5eb405e6191bb81;

library HashLib {
    error LeafIndexOutOfRange();
    error TreeTooHigh();

    /// @dev Returns the EIP-712 typehash of OfferTree(Offer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("OfferTree(Offer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// MARKET_TYPE, OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function offerTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0x004abfc3a2bdb852bd9e193d58623de158d293bff8df82b2c73762b1449a92da;
            if (height == 1) return 0x2b907b506023b7da998b4e05205998675021a6698538b52812412353ba1b5b07;
            if (height == 2) return 0xf3a8fa1ea464758633ee72dfd7bc109d92c69933b1d626583d37c1adc22431f4;
            if (height == 3) return 0xc7aee773c7436e1047be687b497f42b5d2195ebcf80278aa902f65b99ea8d5f9;
            if (height == 4) return 0x1ccd280d009a28babd35e45c7ea1bacc4abecbace69d6ca43bd297618af0d6ea;
            if (height == 5) return 0x976e461f282292a9fc669ed6f8642da97b0853348b8d3b64caf1a63d74535062;
            if (height == 6) return 0xa16c55d7ca5db454b6c0466c695febf8df2b4084481546a26383a48fb573f20b;
            if (height == 7) return 0x15fa4f24cac8ee8dbbc17465043a62700395a7c75c4cc475fe241b6a3424b8bb;
            if (height == 8) return 0x9bf198023231a1c26072e32ee84aa2ed6a1766ca348cceab9bc1065487b6dc82;
            if (height == 9) return 0x7d723919779d24dfca798d2847418afb9d07dccc8aeed8db0f2e54a765e59630;
            return 0xd50fde6271f599771c124dc4d2f3058693c7ef675e733ceffb870fe5f2941524;
        } else {
            if (height == 11) return 0xb1c8d8455bf9b0d65722bc605488eedaf3ca18e32f386c366083af360aed575c;
            if (height == 12) return 0x62306a7da75b4151cbc5a8c2be14ebd9ef413988ceb26330c2b85ea75df64761;
            if (height == 13) return 0x4c05f804d2f0a7edc5d767492018eae312b6f8f9649222f8e7a78745783cd45d;
            if (height == 14) return 0x968c3e8fe32537b97318f74ff109f7e6efa365f25048fc48f474d10981e5d03a;
            if (height == 15) return 0x9c4b06c4bc414cd5ffb0b3d71fd1450393e79bbe73405f2770ee4489175cf734;
            if (height == 16) return 0xe225a68d5feb03db447cc58f3a0ff567cfe7446a73cad24e1781a33696066e90;
            if (height == 17) return 0xa9ef83c85cdc9f01279a32350b39d1e350a51ee9f236a9e6d1be764ec67d2b12;
            if (height == 18) return 0x083f794c8751fba472222de46673bb4386de88d05495f9d2f2c40d96020a95b3;
            if (height == 19) return 0xdfc36aba879c79d4ce19d8620a560d41d19bc9b315758ec93c651e92115d238b;
            if (height == 20) return 0x60f9befb3ea1715092407b29ec59829d55544c89bcd5bde861fef413f2072ddd;
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
