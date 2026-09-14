// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {
    IPriceRatifier,
    Ratification,
    SET_IS_ROOT_RATIFIED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "./interfaces/IPriceRatifier.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS, SET_IS_ROOT_RATIFIED_SUCCESS} from "../libraries/ConstantsLib.sol";
import {HashLib} from "./libraries/HashLib.sol";

/// @dev This ratifier checks that the offer has been ratified by an authorized address in a Merkle tree of offers.
/// @dev The root should correspond to the root of the offer tree, which is a Merkle tree of offers.
/// @dev The leaf index determines each hash order during merkle proof verification.
/// @dev This ratifier must only be used with the Midnight instance at MIDNIGHT.
/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed
/// ratifications are no longer valid.
/// @dev All offers in a tree are expected to share the same maker and ratifier. Otherwise all offers in a
/// tree might not be ratified or unratified by a single call to this function.
contract PriceRatifier is IPriceRatifier {
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

    function isRatified(Offer memory offer, bytes memory ratifierData, address) external view returns (bytes32) {
        (bytes32 root, uint256 leafIndex, bytes32[] memory proof) =
            abi.decode(ratifierData, (bytes32, uint256, bytes32[]));
        require(HashLib.isLeaf(root, HashLib.hashOffer(offer), leafIndex, proof), InvalidProof());
        require(ratification[offer.maker][root].isRootRatified, NotRatified());
        return CALLBACK_SUCCESS;
    }
}
