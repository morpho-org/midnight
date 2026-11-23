// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {BlueSwapBuyCallback} from "./BlueSwapBuyCallback.sol";
import {IBlueSwapBuyCallbackFactory} from "./interfaces/IBlueSwapBuyCallbackFactory.sol";

contract BlueSwapBuyCallbackFactory is IBlueSwapBuyCallbackFactory {
    address public immutable MIDNIGHT;
    address public immutable BLUE;

    mapping(address owner => mapping(bytes32 salt => address)) public callbackOf;
    mapping(address callback => bool) public isBlueSwapBuyCallback;

    constructor(address _midnight, address _blue) {
        MIDNIGHT = _midnight;
        BLUE = _blue;
    }

    function createBlueSwapBuyCallback(address owner, bytes32 salt) external returns (address) {
        address callback = callbackOf[owner][salt] != address(0)
            ? callbackOf[owner][salt]
            : address(new BlueSwapBuyCallback{salt: salt}(owner, MIDNIGHT, BLUE));
        callbackOf[owner][salt] = callback;
        isBlueSwapBuyCallback[callback] = true;

        emit CreateBlueSwapBuyCallback(msg.sender, owner, salt, callback);
        return callback;
    }
}
