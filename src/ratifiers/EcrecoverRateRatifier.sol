// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IEcrecoverRateRatifier, Signature, EIP712_DOMAIN_TYPEHASH} from "./interfaces/IEcrecoverRateRatifier.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS, WAD} from "../libraries/ConstantsLib.sol";
import {TickLib} from "../libraries/TickLib.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {HashLib} from "./libraries/HashLib.sol";

/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed offers are
/// no longer valid.
/// @dev This ratifier checks that the offer has been signed by an authorized address in a Merkle tree of offers.
/// To that end, it expects the ratifier data to contain the signature, the root of the tree, the leaf index of the
/// offer, the proof of the offer in the tree and the start and expiry rate for the offer.
/// @dev The root should correspond to the root of the offer tree, which is a Merkle tree of offers.
/// @dev The leaf index determines each sibling's left/right position.
/// @dev Hashing offers as in EIP-712, which allows clear signing of the tree, credits to Seaport for this mechanism.
/// @dev The maker signs a start and expiry rate instead of a fixed price. Both are WAD-scaled per-second rates.
/// At ratification, the rate is linearly interpolated over the offer lifetime and used as a price limit against
/// the taker's set price.
/// @dev This ratifier must only be used with the Midnight instance at MIDNIGHT.
contract EcrecoverRateRatifier is IEcrecoverRateRatifier {
    using UtilsLib for uint256;

    address public immutable MIDNIGHT;

    mapping(address maker => mapping(bytes32 root => bool)) public isRootCanceled;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    /// @dev All offers in a tree are expected to share the same maker and ratifier. Otherwise all offers in a
    /// tree might not be cancelled by a single call to this function.
    function cancelRoot(address maker, bytes32 root) external {
        require(maker == msg.sender || IMidnight(MIDNIGHT).isAuthorized(maker, msg.sender), Unauthorized());
        isRootCanceled[maker][root] = true;
        emit CancelRoot(msg.sender, maker, root);
    }

    function isRatified(Offer memory offer, bytes memory ratifierData, address) external view returns (bytes32) {
        (
            Signature memory sig,
            bytes32 root,
            uint256 leafIndex,
            bytes32[] memory proof,
            uint256 startRate,
            uint256 expiryRate
        ) = abi.decode(ratifierData, (Signature, bytes32, uint256, bytes32[], uint256, uint256));

        uint256 rate = startRate;
        if (startRate != expiryRate) {
            uint256 elapsed = block.timestamp - offer.start;
            uint256 duration = offer.expiry - offer.start;
            if (expiryRate > startRate) {
                rate = startRate + (expiryRate - startRate).mulDivDown(elapsed, duration);
            } else {
                rate = startRate - (startRate - expiryRate).mulDivDown(elapsed, duration);
            }
        }

        uint256 timeToMaturity = UtilsLib.zeroFloorSub(offer.market.maturity, block.timestamp);
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        if (offer.buy) {
            uint256 priceLimitDown = WAD.mulDivDown(WAD, WAD + rate * timeToMaturity);
            require(offerPrice <= priceLimitDown, WorsePrice());
        } else {
            uint256 priceLimitUp = WAD.mulDivUp(WAD, WAD + rate * timeToMaturity);
            require(offerPrice >= priceLimitUp, WorsePrice());
        }

        require(!isRootCanceled[offer.maker][root], RootCanceled());
        require(
            HashLib.isLeaf(root, HashLib.hashRateOffer(offer, startRate, expiryRate), leafIndex, proof), InvalidProof()
        );
        bytes32 structHash = keccak256(abi.encode(HashLib.rateOfferTreeTypeHash(proof.length), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        // forge-lint: disable-next-item(ecrecover) malleability is ok because the signature is meant to be replayable.
        address _signer = ecrecover(digest, sig.v, sig.r, sig.s);
        require(_signer != address(0), InvalidSignature());
        require(_signer == offer.maker || IMidnight(MIDNIGHT).isAuthorized(offer.maker, _signer), Unauthorized());
        return CALLBACK_SUCCESS;
    }
}
