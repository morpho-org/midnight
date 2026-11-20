// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IReceivableToken} from "../../src/periphery/receivable-token/interfaces/IReceivableToken.sol";
import {IReceivableTokenReceiver} from "../../src/periphery/receivable-token/interfaces/IReceivableTokenReceiver.sol";

/// @dev Test-only non-whitelisted receiver that mints with amount 0 in the hook, whitelisting itself without
/// settling its transient balance.
contract MintReceiver is IReceivableTokenReceiver {
    bytes32 public rootId;
    uint256 public reported;
    bytes32[] public proof;

    function configure(bytes32 _rootId, uint256 _reported, bytes32[] memory _proof) external {
        rootId = _rootId;
        reported = _reported;
        proof = _proof;
    }

    function onReceivableTokenReceived(address, uint256) external {
        IReceivableToken(msg.sender)
            .mint(rootId, address(this), reported, proof, address(this), 0, bytes32(0), bytes32(0));
    }
}
