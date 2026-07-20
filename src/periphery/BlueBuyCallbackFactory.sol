// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {BlueBuyCallback} from "./BlueBuyCallback.sol";
import {IBlueBuyCallbackFactory} from "./interfaces/IBlueBuyCallbackFactory.sol";

contract BlueBuyCallbackFactory is IBlueBuyCallbackFactory {
    address public immutable MIDNIGHT;
    address public immutable BLUE;

    mapping(address owner => address) public callbackOf;
    mapping(address callback => bool) public isBlueCallback;

    constructor(address _midnight, address _blue) {
        MIDNIGHT = _midnight;
        BLUE = _blue;
    }

    function createBlueBuyCallback(address owner) external returns (address) {
        require(callbackOf[owner] == address(0), AlreadyCreated());

        address callback = address(new BlueBuyCallback{salt: bytes32(0)}(owner, MIDNIGHT, BLUE));
        callbackOf[owner] = callback;
        isBlueCallback[callback] = true;

        emit CreateBlueBuyCallback(owner, callback);
        return callback;
    }
}
