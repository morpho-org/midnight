// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IEcrecoverRatifier, Signature, EIP712_DOMAIN_TYPEHASH} from "./interfaces/IEcrecoverRatifier.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";
import {HashLib} from "./HashLib.sol";

/// @dev If block.chainid changes (hard fork), the EIP-712 domain separator changes and previously signed offers are
/// no longer valid.
/// @dev This ratifier checks that the offer has been signed by an authorized address in a Merkle tree of offers.
/// To that end, it expects the ratifier data to contain the signature, the height of the offer in the tree,
/// the root of the tree, and the proof of the offer in the tree.
/// @dev The root should correspond to the root of the offer tree, which is a Merkle tree of offers.
/// @dev If the offers are well-sorted (such that for all nodes, hash(left) <= hash(right)) when given to the wallet,
/// @dev the EIP-712 digest will match the root of the tree. This allows to have clear signing of the tree, credits to
/// Seaport for this mechanism.
contract EcrecoverRatifier is IEcrecoverRatifier {
    address public immutable MIDNIGHT;

    mapping(address maker => mapping(bytes32 root => bool)) public isRootCanceled;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    function cancelRoot(address maker, bytes32 root) external {
        require(maker == msg.sender || IMidnight(MIDNIGHT).isAuthorized(maker, msg.sender), Unauthorized());
        isRootCanceled[maker][root] = true;
        emit CancelRoot(maker, root);
    }

    function isRatified(Offer memory offer, bytes memory ratifierData) external view returns (bytes32) {
        require(msg.sender == MIDNIGHT, NotMidnight());
        (Signature memory sig, uint256 height, bytes32 root, bytes32[] memory proof) =
            abi.decode(ratifierData, (Signature, uint256, bytes32, bytes32[]));
        require(HashLib.isLeaf(root, HashLib.hashOffer(offer), proof), InvalidProof());
        require(!isRootCanceled[offer.maker][root], RootCanceled());
        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(height), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        address _signer = ecrecover(digest, sig.v, sig.r, sig.s);
        require(_signer != address(0), InvalidSignature());
        require(_signer == offer.maker || IMidnight(MIDNIGHT).isAuthorized(offer.maker, _signer), Unauthorized());
        return CALLBACK_SUCCESS;
    }
}
