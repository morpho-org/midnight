// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IMidnight, Market} from "../../src/interfaces/IMidnight.sol";
import {ERC20Lib} from "../../src/periphery/libraries/ERC20Lib.sol";
import {IReceivableToken} from "../../src/periphery/receivable-token/interfaces/IReceivableToken.sol";
import {IReceivableTokenReceiver} from "../../src/periphery/receivable-token/interfaces/IReceivableTokenReceiver.sol";

/// @dev Test-only liquidator that is not whitelisted and holds no capital: it redeems the seized receivable tokens
/// when it receives them, before Midnight pulls the repayment. If `keep` is set, it tries to keep them instead.
contract FlashLiquidator is IReceivableTokenReceiver {
    address internal immutable MIDNIGHT;
    bool public keep;

    constructor(address midnight) {
        MIDNIGHT = midnight;
    }

    function setKeep(bool _keep) external {
        keep = _keep;
    }

    function liquidate(Market memory market, uint256 repaidUnits, address borrower) external {
        IMidnight(MIDNIGHT).liquidate(market, 0, 0, repaidUnits, borrower, true, address(this), address(0), "");
    }

    function onReceivableTokenReceived(address, uint256 amount) external {
        if (keep) return;
        IReceivableToken token = IReceivableToken(msg.sender);
        token.redeem(amount, address(this));
        ERC20Lib.safeApprove(token.asset(), MIDNIGHT, type(uint256).max);
    }
}
