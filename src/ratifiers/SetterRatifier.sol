// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {ISetterRatifier} from "./interfaces/ISetterRatifier.sol";
import {IMidnight, Offer} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";

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

    function onRatify(Offer memory offer, bytes32 root, bytes memory) external view returns (bytes32) {
        require(isRatified[offer.maker][root], NotRatified());
        return CALLBACK_SUCCESS;
    }
}
