// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IReceivableToken} from "../../src/periphery/receivable-token/interfaces/IReceivableToken.sol";
import {IReceivableTokenReceiver} from "../../src/periphery/receivable-token/interfaces/IReceivableTokenReceiver.sol";

/// @dev Test-only non-whitelisted receiver that redeems and forwards configured amounts when it receives tokens, and
/// records what it observed during the call.
contract TransientReceiver is IReceivableTokenReceiver {
    uint256 public redeemAmount;
    address public forwardTo;
    uint256 public forwardAmount;

    uint256 public observedBalance;
    uint256 public observedTransientSupply;

    function configure(uint256 _redeemAmount, address _forwardTo, uint256 _forwardAmount) external {
        redeemAmount = _redeemAmount;
        forwardTo = _forwardTo;
        forwardAmount = _forwardAmount;
    }

    function onReceivableTokenReceived(address, uint256) external {
        IReceivableToken token = IReceivableToken(msg.sender);
        observedBalance = token.balanceOf(address(this));
        observedTransientSupply = token.transientSupply();
        if (redeemAmount > 0) token.redeem(redeemAmount, address(this));
        if (forwardAmount > 0) token.transfer(forwardTo, forwardAmount);
    }
}
