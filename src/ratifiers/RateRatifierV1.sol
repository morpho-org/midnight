// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {
    IRateRatifierV1,
    Ratification,
    SET_IS_ROOT_RATIFIED_TYPEHASH,
    SET_IS_ROOT_RATIFIED_SUCCESS,
    EIP712_DOMAIN_TYPEHASH
} from "./interfaces/IRateRatifierV1.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS, WAD} from "../libraries/ConstantsLib.sol";
import {TickLib} from "../libraries/TickLib.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {HashLib} from "./libraries/HashLib.sol";

/// @dev This ratifier checks that an authorized address has ratified the root of a Merkle tree of rate offers, and
/// that the offer is a leaf in that tree.
/// @dev The ratifier data must contain the root, the leaf index, the Merkle proof, the start and expiry rates and the
/// offer's allowed taker.
/// @dev The leaf index determines each sibling's left/right position during Merkle proof verification.
/// @dev The maker sets a start and expiry rate instead of a fixed price. Both are WAD-scaled per-second rates.
/// At ratification, the rate is linearly interpolated over the offer lifetime and used as a price limit against
/// the taker's set price.
/// @dev A root can also be ratified with a signature.
/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed
/// ratifications are no longer valid.
/// @dev This ratifier must only be used with the Midnight instance at MIDNIGHT.
/// @dev All offers in a tree are expected to share the same maker and ratifier. Otherwise all offers in a
/// tree might not be ratified or unratified by a single call to this function.
contract RateRatifierV1 is IRateRatifierV1 {
    using UtilsLib for uint256;

    address public immutable MIDNIGHT;

    mapping(address maker => mapping(bytes32 root => Ratification)) public ratification;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    function isRootRatified(address maker, bytes32 root) public view returns (bool) {
        return ratification[maker][root].isRootRatified;
    }

    function setIsRootRatified(address maker, bytes32 root, bool newIsRootRatified) external returns (bytes32) {
        require(maker == msg.sender || IMidnight(MIDNIGHT).isAuthorized(maker, msg.sender), Unauthorized());
        ratification[maker][root].isRootRatified = newIsRootRatified;
        emit SetIsRootRatified(msg.sender, maker, root, newIsRootRatified);
        return SET_IS_ROOT_RATIFIED_SUCCESS;
    }

    /// @dev Allows clear signing of the root through EIP712.
    /// @dev Permissioned to not let any arbitrary actor to submit the signed ratification.
    function setIsRootRatifiedWithSig(
        address maker,
        bytes32 root,
        bool newIsRootRatified,
        uint128 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes32) {
        require(maker == msg.sender || IMidnight(MIDNIGHT).isAuthorized(maker, msg.sender), Unauthorized());
        require(deadline >= block.timestamp, DeadlineExpired());
        bytes32 hashStruct =
            keccak256(abi.encode(SET_IS_ROOT_RATIFIED_TYPEHASH, maker, root, newIsRootRatified, nonce, deadline));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        // forge-lint: disable-next-item(ecrecover) malleability is ok thanks to the nonce.
        address _signer = ecrecover(digest, v, r, s);
        require(_signer != address(0), InvalidSignature());
        require(_signer == maker || IMidnight(MIDNIGHT).isAuthorized(maker, _signer), Unauthorized());
        Ratification memory currentRatification = ratification[maker][root];
        if (nonce == currentRatification.rootNonce) {
            ratification[maker][root] = Ratification({isRootRatified: newIsRootRatified, rootNonce: nonce + 1});
        } else {
            require(nonce < currentRatification.rootNonce, InvalidNonce());
            require(currentRatification.isRootRatified == newIsRootRatified, RatifiedStatusChanged());
        }
        emit SetIsRootRatifiedWithSig(_signer, maker, root, newIsRootRatified, nonce, currentRatification.rootNonce);
        return SET_IS_ROOT_RATIFIED_SUCCESS;
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function isRatified(Offer memory offer, bytes memory ratifierData, address taker) external view returns (bytes32) {
        (
            bytes32 root,
            uint256 leafIndex,
            bytes32[] memory proof,
            uint256 startRate,
            uint256 expiryRate,
            address allowedTaker
        ) = abi.decode(ratifierData, (bytes32, uint256, bytes32[], uint256, uint256, address));
        require(allowedTaker == address(0) || taker == allowedTaker, UnauthorizedTaker());
        // to avoid returning an inconsistent price when not called from Midnight.
        require(block.timestamp <= offer.expiry, OfferExpired());
        uint256 rate;
        if (startRate == expiryRate) {
            rate = startRate;
        } else {
            rate = startRate > expiryRate
                ? startRate
                    - (startRate - expiryRate).mulDivDown(block.timestamp - offer.start, offer.expiry - offer.start)
                : startRate
                    + (expiryRate - startRate).mulDivDown(block.timestamp - offer.start, offer.expiry - offer.start);
        }

        uint256 timeToMaturity = UtilsLib.zeroFloorSub(offer.market.maturity, block.timestamp);
        uint256 offerPrice = TickLib.tickToPrice(offer.tick);
        if (offer.buy) {
            require(offerPrice <= WAD.mulDivDown(WAD, WAD + rate * timeToMaturity), WorsePrice());
        } else {
            require(offerPrice >= WAD.mulDivUp(WAD, WAD + rate * timeToMaturity), WorsePrice());
        }

        require(
            HashLib.isLeaf(root, HashLib.hashRateOffer(offer, startRate, expiryRate, allowedTaker), leafIndex, proof),
            InvalidProof()
        );
        require(ratification[offer.maker][root].isRootRatified, NotRatified());
        return CALLBACK_SUCCESS;
    }
}
