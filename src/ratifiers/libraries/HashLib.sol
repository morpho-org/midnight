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
/// @dev keccak256(bytes.concat(RATE_OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)).
bytes32 constant RATE_OFFER_TYPEHASH = 0xc20e58558abaad23c23a8647fddfd5ddfb4a2ffccf572b8ff814fe7a3a460be9;

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

    /// @dev Returns the EIP-712 typehash of RateOfferTree(RateOffer[2]...[2] offerTree) with height levels.
    /// @dev Same as keccak256(bytes.concat("RateOfferTree(RateOffer[2]...[2] offerTree)", COLLATERAL_PARAMS_TYPE,
    /// MARKET_TYPE, RATE_OFFER_TYPE)), where RATE_OFFER_TYPE encodes an Offer with `tick` replaced by `startRate`
    /// (uint256), `expiryRate` (uint256), and `onlyTaker` (address).
    /// @dev Reverts if height is greater than 20.
    function rateOfferTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0x432d39d1800f18b61016b18160c33aa5be7ea50a363e23c7b39e279f7ad90813;
            if (height == 1) return 0x187abb8e4e01a2af42ccd3e8f33b3436ea3807fa80bd0dc1ebef76e6b5afd549;
            if (height == 2) return 0x1bf94ba27072b890a8e1a716aeade805a1747b96b278a4d67004ae2339a84835;
            if (height == 3) return 0xfb5c5d206fec1495df297e918bfb2f832054b929800c4ff9b5c6da972e048e0b;
            if (height == 4) return 0x411e5d9249dbc4864f4d8493ec03a49f0563c33dd6d17318c3f9a8159785ec2c;
            if (height == 5) return 0x86021bbe8de8223faf93faf1915c32db89d18a09fc46fe709f6bd8ed35092e07;
            if (height == 6) return 0x117cbd16a73d91a9d4b1844eccf96103f2254d56052a5694b549109c5f6a5de9;
            if (height == 7) return 0x5f00bae419869754bd829d49c76b84658219813af8f84cd1a8471ddcac83e011;
            if (height == 8) return 0x6337215578f0ebbc1d3da8ae55c06c514354cc11609208b6cb6f4fc98db49d44;
            if (height == 9) return 0x4f19161c3534c5ef22ae176169fa67d8e509d74d38d7978396bef7af8969bdee;
            return 0xb04771f96f338665e042882ff1b5df7c7921002e68f672134f6a8c4473cb35b7;
        } else {
            if (height == 11) return 0xa54c45468c14af4e8d8e237925a2935fe93ebf4d7242aec43c6a0f5cf4809f59;
            if (height == 12) return 0xdbfc80365ca65b7a318e8ffe337d76df31cf905d82b33212cedb8e1036972d9d;
            if (height == 13) return 0x2834368b93375a3d076141ceb2e1a187211c098572964fde6581576f3745e367;
            if (height == 14) return 0x12dd046087b45d5bd44f526da265183678af49f70de6ea6bfe89f1507a345039;
            if (height == 15) return 0xe1f607c460298d572e5bb901eed1fec6a05abaaeda61471632eef590d1962fb7;
            if (height == 16) return 0x5f312dab99e63ee0198f91530c0cfe3ab92c15c1354b3cd91a8010a8579ebfc5;
            if (height == 17) return 0x06465b5a1d66cfe3832f851954292f2a088786da6240ab3ef01a21bba323ffbf;
            if (height == 18) return 0x49cca45f89d442f8b2082ea84741c55dd71deec3e1d82f7c7fd4ab5a66fb611e;
            if (height == 19) return 0x7789b52de5afede1651a2e2b53b65b3da3181d989281c218165cc47bda16a078;
            if (height == 20) return 0x3c2f1b446e6861db3592ac3f2db2e6d8b6d4c14ce8a5061ad43596fdd8841b13;
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

    /// @dev Computes the EIP-712 hash struct of a RateOffer (offer with `tick` replaced by `startRate`,
    /// `expiryRate`, and `onlyTaker`).
    function hashRateOffer(Offer memory offer, uint256 startRate, uint256 expiryRate, address onlyTaker)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                RATE_OFFER_TYPEHASH,
                hashMarket(offer.market),
                offer.buy,
                offer.maker,
                offer.start,
                offer.expiry,
                startRate,
                expiryRate,
                onlyTaker,
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
