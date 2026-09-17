// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IPriceRatifierV1, Ratification, EIP712_DOMAIN_TYPEHASH} from "./interfaces/IPriceRatifierV1.sol";
import {SET_IS_ROOT_RATIFIED_SUCCESS} from "./interfaces/IRatifiersV1Common.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";
import {HashLib} from "./libraries/HashLib.sol";

/// @dev This ratifier checks that an authorized address has ratified the root of a Merkle tree of offers, and
/// that the offer is a leaf in that tree.
/// @dev The ratifier data must contain the root, the leaf index, the Merkle proof and the offer's allowed taker (or
/// address(0)).
/// @dev The leaf index determines each sibling's left/right position during Merkle proof verification.
/// @dev A root can also be ratified with a signature.
/// @dev Hashing offers as in EIP-712, which allows clear signing of the tree in setIsRootRatifiedWithSig, credits
/// to Seaport for this mechanism.
/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed
/// ratifications are no longer valid.
/// @dev This ratifier must only be used with the Midnight instance at MIDNIGHT.
/// @dev All offers in a tree are expected to share the same maker and ratifier. Otherwise all offers in a
/// tree might not be ratified or unratified by a single call to either root setter.
contract PriceRatifierV1 is IPriceRatifierV1 {
    address public immutable MIDNIGHT;

    mapping(address maker => mapping(bytes32 root => Ratification)) public ratification;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    function isRootRatified(address maker, bytes32 root) public view returns (bool) {
        return ratification[maker][root].isRootRatified;
    }

    function rootNonce(address maker, bytes32 root) public view returns (uint128) {
        return ratification[maker][root].rootNonce;
    }

    function setIsRootRatified(address maker, bytes32 root, bool newIsRootRatified) external returns (bytes32) {
        require(maker == msg.sender || IMidnight(MIDNIGHT).isAuthorized(maker, msg.sender), Unauthorized());
        ratification[maker][root].isRootRatified = newIsRootRatified;
        emit SetIsRootRatified(msg.sender, maker, root, newIsRootRatified);
        return SET_IS_ROOT_RATIFIED_SUCCESS;
    }

    /// @dev Permissioned to not let people extract the signature of a batch and start taking before or take even though
    /// the batch reverted.
    function setIsRootRatifiedWithSig(
        address maker,
        bytes32 root,
        uint256 height,
        bool newIsRootRatified,
        uint128 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes32) {
        require(maker == msg.sender || IMidnight(MIDNIGHT).isAuthorized(maker, msg.sender), Unauthorized());
        require(deadline >= block.timestamp, DeadlineExpired());
        bytes32 hashStruct = keccak256(
            abi.encode(
                HashLib.priceRatifierV1OfferTreeTypeHash(height), maker, root, newIsRootRatified, nonce, deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        // forge-lint: disable-next-item(ecrecover) malleability is ok thanks to the nonce.
        address _signer = ecrecover(digest, v, r, s);
        require(_signer != address(0), InvalidSignature());
        require(_signer == maker || IMidnight(MIDNIGHT).isAuthorized(maker, _signer), Unauthorized());
        Ratification memory _ratification = ratification[maker][root];
        if (nonce == _ratification.rootNonce) {
            ratification[maker][root] = Ratification({isRootRatified: newIsRootRatified, rootNonce: nonce + 1});
        } else {
            require(nonce < _ratification.rootNonce, InvalidNonce());
            require(_ratification.isRootRatified == newIsRootRatified, RatifiedStatusChanged());
        }
        emit SetIsRootRatifiedWithSig(
            msg.sender, _signer, maker, root, height, newIsRootRatified, nonce, _ratification.rootNonce
        );
        return SET_IS_ROOT_RATIFIED_SUCCESS;
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function isRatified(Offer memory offer, bytes memory ratifierData, address taker) external view returns (bytes32) {
        (bytes32 root, uint256 leafIndex, bytes32[] memory proof, address allowedTaker) =
            abi.decode(ratifierData, (bytes32, uint256, bytes32[], address));
        require(allowedTaker == address(0) || taker == allowedTaker, UnauthorizedTaker());
        require(
            HashLib.isLeaf(root, HashLib.hashPriceRatifierV1Offer(offer, allowedTaker), leafIndex, proof),
            InvalidProof()
        );
        require(ratification[offer.maker][root].isRootRatified, NotRatified());
        return CALLBACK_SUCCESS;
    }
}
