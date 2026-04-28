// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {Obligation} from "../interfaces/IMidnight.sol";
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
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256,
        bytes memory data
    ) external returns (bytes32) {
        require(msg.sender == MIDNIGHT, "unauthorized");
        bytes32 otherObligationId = abi.decode(data, (bytes32));
        Obligation memory otherObligation = abi.decode(address(uint160(uint256(otherObligationId))).code, (Obligation));
        Midnight(MIDNIGHT).withdraw(otherObligation, buyerAssets, buyer, address(this));
        IERC20(obligation.loanToken).approve(MIDNIGHT, buyerAssets);
        return CALLBACK_SUCCESS;
    }
}
