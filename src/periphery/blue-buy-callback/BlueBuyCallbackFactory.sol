// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {BlueBuyCallback} from "./BlueBuyCallback.sol";
import {IBlueBuyCallbackFactory} from "./interfaces/IBlueBuyCallbackFactory.sol";

contract BlueBuyCallbackFactory is IBlueBuyCallbackFactory {
    address public immutable MIDNIGHT;
    address public immutable BLUE;

    mapping(address owner => mapping(bytes32 salt => address)) public callbackOf;
    mapping(address callback => bool) public isBlueBuyCallback;

    constructor(address _midnight, address _blue) {
        MIDNIGHT = _midnight;
        BLUE = _blue;
    }

    function createBlueBuyCallback(address owner, bytes32 salt) external returns (address) {
        address callback = callbackOf[owner][salt] != address(0)
            ? callbackOf[owner][salt]
            : address(new BlueBuyCallback{salt: salt}(owner, MIDNIGHT, BLUE));
        callbackOf[owner][salt] = callback;
        isBlueBuyCallback[callback] = true;

        // forge-lint: disable-next-item(reentrancy-events) as the ordering is already safe: both state writes
        // precede the emit, and the only external call is the CREATE2 above, whose constructor calls the immutable
        // BLUE; a reentrant call with the same salt reverts on the CREATE2 address collision.
        emit CreateBlueBuyCallback(msg.sender, owner, salt, callback);
        return callback;
    }
}
