// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IRatifier} from "../interfaces/IRatifier.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";

contract SetterRatifier is IRatifier {
    event SetApproval(address indexed maker, bytes32 indexed root, bool newApproval);

    address public immutable MIDNIGHT;

    mapping(address maker => mapping(bytes32 root => bool)) public isRatified;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    function setIsRatified(address maker, bytes32 root, bool newApproval) public {
        require(maker == msg.sender || IMidnight(MIDNIGHT).isAuthorized(maker, msg.sender), "unauthorized");
        isRatified[maker][root] = newApproval;
        emit SetApproval(maker, root, newApproval);
    }

    function onRatify(Offer memory offer, bytes32 root, bytes memory) external view returns (bytes32) {
        require(isRatified[offer.maker][root], "not approved");
        return CALLBACK_SUCCESS;
    }
}
