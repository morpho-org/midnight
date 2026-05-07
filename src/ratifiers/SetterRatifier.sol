// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {ISetterRatifier} from "./interfaces/ISetterRatifier.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";
import {HashLib} from "./HashLib.sol";
import {MerkleLib} from "../libraries/MerkleLib.sol";

/// @dev This ratifier checks that the offer has been ratified by an authorized address in a Merkle tree of offers.
/// To that end, it expects the ratifier data to contain the root of the tree and the proof of the offer in the
/// tree.
contract SetterRatifier is ISetterRatifier {
    address public immutable MIDNIGHT;

    mapping(address maker => mapping(bytes32 root => bool)) public isRatified;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    function setIsRatified(address maker, bytes32 root, bool newIsRatified) public {
        require(maker == msg.sender || IMidnight(MIDNIGHT).isAuthorized(maker, msg.sender), Unauthorized());
        isRatified[maker][root] = newIsRatified;
        emit SetIsRatified(maker, root, newIsRatified);
    }

    function onRatify(Offer memory offer, bytes memory ratifierData) external view returns (bytes32) {
        require(msg.sender == MIDNIGHT, NotMidnight());
        (bytes32 root, bytes32[] memory proof) = abi.decode(ratifierData, (bytes32, bytes32[]));
        require(isRatified[offer.maker][root], NotRatified());
        require(MerkleLib.isLeaf(root, HashLib.hashOffer(offer), proof), InvalidProof());
        return CALLBACK_SUCCESS;
    }
}
