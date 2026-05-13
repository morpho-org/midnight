// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {ISetterRatifier} from "./interfaces/ISetterRatifier.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";
import {HashLib} from "./HashLib.sol";

/// @dev This ratifier checks that the offer has been ratified by an authorized address in a Merkle tree of offers.
/// To that end, it expects the ratifier data to contain the root of the tree and the proof of the offer in the tree.
/// @dev The root should correspond to the root of the offer tree, which is a Merkle tree of offers.
/// @dev If the offers are well-sorted (such that for all nodes, hash(left) <= hash(right)) when given to the wallet,
/// @dev the EIP-712 digest will match the root of the tree. This allows to have clear signing of the tree, credits to
/// Seaport for this mechanism.
contract SetterRatifier is ISetterRatifier {
    address public immutable MIDNIGHT;

    mapping(address maker => mapping(bytes32 root => bool)) public isRootRatified;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    function setIsRootRatified(address maker, bytes32 root, bool newIsRootRatified) public {
        require(maker == msg.sender || IMidnight(MIDNIGHT).isAuthorized(maker, msg.sender), Unauthorized());
        isRootRatified[maker][root] = newIsRootRatified;
        emit SetIsRootRatified(maker, root, newIsRootRatified);
    }

    function isRatified(Offer memory offer, bytes memory ratifierData) external view returns (bytes32) {
        require(msg.sender == MIDNIGHT, NotMidnight());
        (bytes32 root, bytes32[] memory proof) = abi.decode(ratifierData, (bytes32, bytes32[]));
        require(HashLib.isLeaf(root, HashLib.hashOffer(offer), proof), InvalidProof());
        require(isRootRatified[offer.maker][root], NotRatified());
        return CALLBACK_SUCCESS;
    }
}
