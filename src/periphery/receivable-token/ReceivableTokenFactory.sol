// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {ReceivableToken} from "./ReceivableToken.sol";
import {IReceivableTokenFactory} from "./interfaces/IReceivableTokenFactory.sol";

contract ReceivableTokenFactory is IReceivableTokenFactory {
    address public immutable midnight;

    mapping(address account => bool) public isReceivableToken;

    constructor(address _midnight) {
        midnight = _midnight;
        emit Constructor(_midnight);
    }

    /// @dev Returns the address of the deployed ReceivableToken.
    function createReceivableToken(
        address owner,
        address asset,
        string memory name,
        string memory symbol,
        bytes32 root,
        bytes32 salt
    ) external returns (address) {
        address newReceivableToken =
            address(new ReceivableToken{salt: salt}(midnight, asset, owner, name, symbol, root));

        isReceivableToken[newReceivableToken] = true;
        emit CreateReceivableToken(owner, asset, salt, newReceivableToken, name, symbol, root, msg.sender);

        return newReceivableToken;
    }
}
