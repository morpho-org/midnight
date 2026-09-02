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
bytes32 constant RATE_OFFER_TYPEHASH = 0x5491810bddcc38045a365fa4bd5d0074db4da26f53080aebff9cc78e43733398;

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
    /// MARKET_TYPE, RATE_OFFER_TYPE)).
    /// @dev Reverts if height is greater than 20.
    function rateOfferTreeTypeHash(uint256 height) internal pure returns (bytes32) {
        if (height <= 10) {
            if (height == 0) return 0xfc27b18e42dece03393ff3c5e4c03ad6887d0195f9692cee6a5689e7ec997496;
            if (height == 1) return 0xdedd609540f281ef568856cfb0c998a7e1753c921dd3c5b1959111f310085e86;
            if (height == 2) return 0xe99b89e3535b116271c1b166057380becf27459cc0a60f8224a64e60b4f18647;
            if (height == 3) return 0xd3dbbd2ef3611409acae94c78411699ec0c6a779ecca6e751bccb8ac0ea37c9a;
            if (height == 4) return 0x7d81bb4334b13363a365ad0cff8c9b358f190efe4a642c62c090fe3e3e574079;
            if (height == 5) return 0x16c449f18ce3d0e37fd6ab886e5553f7166a70f66e961e21dffe1c43e41bf457;
            if (height == 6) return 0x15bf478fb9736ce573b3153250c30a40e7d09d7b2006758dfb34794ed1af5f44;
            if (height == 7) return 0x8cbf116de85a0df3167d845fb363de5aa8482ed7d76a77b99045200ca132040a;
            if (height == 8) return 0xb08255559ef336aeb73e331f762fdb65520de57c161e3a3928d7824e3038342e;
            if (height == 9) return 0x44e763e537b4a2098f98a41fe8137bea1cb0987ea6857e863b227d1d36d596b7;
            return 0x3e257e923d3cf53aa42b78fe26dfc6bdcb8519a85adc7e3c45c46bd7fb60a36b;
        } else {
            if (height == 11) return 0x2b0f66f50b04d3d39250d359b746b26d6997879f3f288d0507907cc5088fcae7;
            if (height == 12) return 0xc3fa18db0f190cb0e75b2a7e7779ed1f5951d863aecec032a9c4f84652a0f049;
            if (height == 13) return 0xdf8b6e14b8be33a60678bcc4bc785967ebbd8dfd69df6998ced2dfef63e4ac7d;
            if (height == 14) return 0xeee0f2fb71a61a1dfd579b1bae97bef341907016040be6823a9255a1fe64a7ed;
            if (height == 15) return 0xa5255f90eb0d5fe820fe3d3a7fc0abdb5318ff6d965651b0d051471713ffad7a;
            if (height == 16) return 0x7d699f9f1202721e42df0aae191cfd88583de2d8e2e0d20c9a6c2ff2193a1c1c;
            if (height == 17) return 0x7449ed31ef3fd8fe3ae08dbf15494833e7f917c20b406e60e878cd11f6e235a7;
            if (height == 18) return 0xd601cfa1c254730b879d45a93b9b89e34549c6cd483e933d07baca3cf57eca24;
            if (height == 19) return 0xa5262709c837f4532286b41ffa4e56125a84b05453a7c26795956d9bcfcede8e;
            if (height == 20) return 0xb44343c7cae314d4afb366a68aa8145916587454237c261856a95d8b347a4b89;
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

    /// @dev Computes the EIP-712 hash struct of a RateOffer (offer with `tick` replaced by `startRate` and
    /// `expiryRate`).
    function hashRateOffer(Offer memory offer, uint256 startRate, uint256 expiryRate) internal pure returns (bytes32) {
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
