// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Offer, Market, CollateralParams} from "../../interfaces/IMidnight.sol";

/// @dev keccak256("CollateralParams(address token,uint256 lltv,uint256 liquidationCursor,address oracle)").
bytes32 constant COLLATERAL_PARAMS_TYPEHASH = 0x39ed3f928d24fd00574b1a02aba9c2483abcf5d9a3a366118c9a5aa29885b841;
/// @dev keccak256(bytes.concat(MARKET_TYPE, COLLATERAL_PARAMS_TYPE)).
bytes32 constant MARKET_TYPEHASH = 0x510b3862f3816a109c9340b76972e8a30984246be06e034ae12ed2934220391a;
/// @dev keccak256(bytes.concat(OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant OFFER_TYPEHASH = 0x9905214264a9fb7b6cc1b0e33db7a04687c6e4185a84755d29914314aa9d8906;
/// @dev keccak256(bytes.concat(RATE_RATIFIER_V1_OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant RATE_RATIFIER_V1_OFFER_TYPEHASH = 0x8e0f9c17bf7e919b5f22e8c6c4e787905f45864a4be441067bbd2e65b35c3de1;
/// @dev keccak256(bytes.concat(PRICE_RATIFIER_V1_OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant PRICE_RATIFIER_V1_OFFER_TYPEHASH = 0x62a94097fbcb9b56e3cf7b4f7bb075b49540b1364815434ff4b16bc4decb303d;

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

    /// @dev Returns the EIP-712 typehash of SetIsRootRatified(address maker,PriceRatifierV1Offer[2]...[2]
    /// offerTree,bool newIsRootRatified,uint128 nonce,uint256 deadline) with height levels.
    /// @dev Same as keccak256(bytes.concat("SetIsRootRatified(address maker,PriceRatifierV1Offer[2]...[2]
    /// offerTree,bool newIsRootRatified,uint128 nonce,uint256 deadline)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE,
    /// PRICE_RATIFIER_V1_OFFER_TYPE)), where PriceRatifierV1Offer encodes an Offer with an `allowedTaker` (address).
    /// @dev Reverts if height is greater than 20.
    function priceRatifierV1OfferTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0xb1ace380d05f4ac34ef45873700875be9df2e200d2ec832bf092cb8437f4eae5;
            if (height == 1) return 0xa303fe781c624443882aa9e8b99cdf2826603a671a02c25603f88391708771c0;
            if (height == 2) return 0x139e949dbfaf7e1bf9d8cd78cdf4a4efb355ff8ba71c82b6815c104d36fe8555;
            if (height == 3) return 0xe4ff26f1951cb73292eae37be50510a26801c09959f694fe47cb6f19f443cb67;
            if (height == 4) return 0xf1dd23aebe9380e4db836fbf99ae973221887193e697bc848e75cca7fcadcbe2;
            if (height == 5) return 0xb11a39e0628162c6a7560d8fd0a95d270593378889f68618a7af795a9474d48a;
            if (height == 6) return 0x4a72399512ed84e61f3396ad2bd12cb5415a9732537eb76a6f1bf1ed30cddee1;
            if (height == 7) return 0xa030e3a96cdd2e5e7e4757c48df44dff49854ec9de31dc277c62d1e1060cc17a;
            if (height == 8) return 0x7733df74e13b8e85284151c34ac2476dbd241e5c5e496694e257c74b6a8acee8;
            if (height == 9) return 0x83a1f7ea0262ebc3ea8cfa820a9be63fc83086dfea6ee3268da922f45fee5b13;
            return 0x0968b576e420ba33e2eab2c8a766192ba853fb3da4aca87a083a4dfe53e642f0;
        } else {
            if (height == 11) return 0xc760e9254ae8c8a80cb9b379cc767f99110a4066a307275feebaa39095a6d140;
            if (height == 12) return 0x3b977afee7bd3ee24be1392b0aa286d8489e63c12dff83a82784fd1c7fabc4bf;
            if (height == 13) return 0x6055a19da25d0456eafefd697fcd51c7df2705070448ca87fc430d1b33734535;
            if (height == 14) return 0x06b9fa75846ce4b8134e8f9176141d01588ab142d04409f85c415fd402b5de67;
            if (height == 15) return 0xfc0b6b6e102a0747a311ed5d50deef2c8f4560e16cff7d952ce40e98c5c5a7d5;
            if (height == 16) return 0xfca320e7d38a66e841090d6a820726d4ea6b9dcfb64a5ba42e53ea214489887b;
            if (height == 17) return 0x2736bed4e235ee2c705fb0fb9140354b4d017d6da049f32556b9d6549e5f680b;
            if (height == 18) return 0x2efe1fd57f0abc80ee7064c7e0588de2516087cee3e3371f8c9a8e63847f3825;
            if (height == 19) return 0x768858c6173f99ca94a134ac6636f8a2518203dacb257a1ab0a5e0e57b0ffd26;
            if (height == 20) return 0x9498f487d5d006cef8262f8375d47aaf99f3b160c07a9154d5c0b052a3866e34;
            revert TreeTooHigh();
        }
    }

    /// @dev Returns the EIP-712 typehash of SetIsRootRatified(address maker,RateRatifierV1Offer[2]...[2]
    /// offerTree,bool newIsRootRatified,uint128 nonce,uint256 deadline) with height levels.
    /// @dev Same as keccak256(bytes.concat("SetIsRootRatified(address maker,RateRatifierV1Offer[2]...[2]
    /// offerTree,bool newIsRootRatified,uint128 nonce,uint256 deadline)", COLLATERAL_PARAMS_TYPE, MARKET_TYPE,
    /// RATE_RATIFIER_V1_OFFER_TYPE)), where RateRatifierV1Offer encodes an Offer with `tick` replaced by
    /// `rate` (uint256) and an `allowedTaker` (address).
    /// @dev Reverts if height is greater than 20.
    function rateRatifierV1OfferTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0xc4253cea37da3bbb411fff0b44a6e9d2688289a08ede97eda83c6071ca73e4a6;
            if (height == 1) return 0x68def127c4f986ef73496dab9c783abaac0e15c2c431dccf12bd56afe7d52ad8;
            if (height == 2) return 0x49171b2c7afc3c2ee325bc36dd3836b4efdaccb4b0e69857ca4802d4504d17f4;
            if (height == 3) return 0x3dadef1d80f6a703648d1999643c546a22fa58195472e921b947c8645bdef7d3;
            if (height == 4) return 0xa9588e060964bc515a9e9eef35294fda8fdc0761c8b46119510c189e7bc8b650;
            if (height == 5) return 0xe979e61f79c4b26004001d57c2a66b4a04d53b3608e2f1bcfe27cfd7dec43e14;
            if (height == 6) return 0x13fe440e0682f5ada6103f21a4c2032a14d14b55b8c1cbf88704106eab8c34e6;
            if (height == 7) return 0x0ab76fd280316abe2ea2bdbb0c92d7775110dee7c2ed850c2844953570d69db3;
            if (height == 8) return 0xc8e75af0f3e4f1f9a268eaaf3c382179da6b187a6ec595697683e73b0664d727;
            if (height == 9) return 0x89b340f8331ee326bfd33f56049f82c4d10cf0e1853d5ee145525319f85f714c;
            return 0x7ed2ac551b20dd5806efb9d885cffe0ea127f15d5f67144e51af20d5af868086;
        } else {
            if (height == 11) return 0xe08872bdb32c4d112f5b58383f9608fa282930fdc1ed17c2a5f4f29f583e7362;
            if (height == 12) return 0x6ba12f22489ba319c1dfb9040755a73e59037f47d28af3658fc18fdba4507f7d;
            if (height == 13) return 0x5a3d9742d7062454d2d2efc8480a9833367b86f1737f771d4fc05fbf9bf27e9d;
            if (height == 14) return 0x62ac53698660ca5fe578d64e65fdcae34fef97c819061a80c842954d666264e1;
            if (height == 15) return 0xccd7c440dd782374a52b11168705ebf6b63cd81dbfaaf1c14bf794cff6a943bf;
            if (height == 16) return 0x9adf2e5976891693bf5baadef999033f15bb896db52c4096bdfb5eaa0b731107;
            if (height == 17) return 0xf090b8584863dc2767a68251bca55216f5ef95878dd098d36bca59d09bdff0a2;
            if (height == 18) return 0xb49bc5b705b928c0a7a9d244ba706719d82a0aec4a0ec165263e4fb740b11c35;
            if (height == 19) return 0x03f732308990e47a45b63e1f98af30f3b35bd6f930e2bcc08759dfc91afcb1c2;
            if (height == 20) return 0xa90191f8f9bf3412255a92ee907857050fbd446516e63218ad832993abe4ba10;
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

    /// @dev Computes the EIP-712 hash struct of a PriceRatifierV1Offer (Offer with an additional `allowedTaker`).
    function hashPriceRatifierV1Offer(Offer memory offer, address allowedTaker) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                PRICE_RATIFIER_V1_OFFER_TYPEHASH,
                hashMarket(offer.market),
                offer.buy,
                offer.maker,
                offer.start,
                offer.expiry,
                offer.tick,
                allowedTaker,
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

    /// @dev Computes the EIP-712 hash struct of a RateRatifierV1Offer (Offer with `tick` replaced by `rate` and
    /// `allowedTaker`).
    function hashRateRatifierV1Offer(Offer memory offer, uint256 rate, address allowedTaker)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                RATE_RATIFIER_V1_OFFER_TYPEHASH,
                hashMarket(offer.market),
                offer.buy,
                offer.maker,
                offer.start,
                offer.expiry,
                rate,
                allowedTaker,
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
