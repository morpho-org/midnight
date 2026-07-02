// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {ISetterRatifier} from "./interfaces/ISetterRatifier.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";
import {HashLib} from "./libraries/HashLib.sol";

/// @dev This ratifier checks that the offer has been ratified by an authorized address in a Merkle tree of offers.
/// To that end, it expects the ratifier data to contain the root of the tree, the leaf index of the offer in the tree,
/// and the proof of the offer in the tree.
/// @dev The root should correspond to the root of the offer tree, which is a Merkle tree of offers.
/// @dev The leaf index determines each hash order during merkle proof verification.
contract SetterRatifier is ISetterRatifier {
    mapping(address maker => mapping(bytes32 root => bool)) public isRootRatified;

    /// @dev All offers in a tree are expected to share the same maker and ratifier. Otherwise all offers in a
    /// tree might not be ratified or unratified by a single call to this function.
    function setIsRootRatified(Offer memory offer, bytes32 root, bool newIsRootRatified) external {
        require(
            offer.maker == msg.sender || IMidnight(offer.market.midnight).isAuthorized(offer.maker, msg.sender),
            Unauthorized()
        );
        isRootRatified[offer.maker][root] = newIsRootRatified;
        emit SetIsRootRatified(msg.sender, offer.maker, root, newIsRootRatified);
    }

    function isRatified(Offer memory offer, bytes memory ratifierData) external view returns (bytes32) {
        (bytes32 root, uint256 leafIndex, bytes32[] memory proof) =
            abi.decode(ratifierData, (bytes32, uint256, bytes32[]));
        require(HashLib.isLeaf(root, HashLib.hashOffer(offer), leafIndex, proof), InvalidProof());
        require(isRootRatified[offer.maker][root], NotRatified());
        return CALLBACK_SUCCESS;
    }
}
