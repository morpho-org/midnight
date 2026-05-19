// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {Market} from "../interfaces/IMidnight.sol";
import {Midnight} from "../Midnight.sol";
import {IBuyCallback} from "../interfaces/ICallbacks.sol";
import {IERC20} from "./IERC20.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";

contract ObligationLenderCallback is IBuyCallback {
    address public immutable MIDNIGHT;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    /// @dev Callback to withdraw funds from another Midnight obligation.
    /// @dev The callback contract should be authorized to withdraw funds on behalf of the lender.
    function onBuy(
        bytes32,
        Market memory market,
        address buyer,
        uint256 buyerAssets,
        uint256,
        bytes memory data
    ) external returns (bytes32) {
        require(msg.sender == MIDNIGHT, "unauthorized");
        bytes32 otherMarketId = abi.decode(data, (bytes32));
        Market memory otherMarket = abi.decode(address(uint160(uint256(otherMarketId))).code, (Market));
        Midnight(MIDNIGHT).withdraw(otherMarket, buyerAssets, buyer, address(this));
        IERC20(market.loanToken).approve(MIDNIGHT, buyerAssets);
        return CALLBACK_SUCCESS;
    }
}
