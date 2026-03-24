// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {Obligation} from "../interfaces/IMidnight.sol";
import {Midnight} from "../Midnight.sol";
import {ICallbacks} from "../interfaces/ICallbacks.sol";

contract ObligationLenderCallback is ICallbacks {
    address public immutable MIDNIGHT;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    /// @dev Callback to withdraw funds from another Midnight obligation.
    /// @dev The callback contract should be authorized to withdraw funds on behalf of the lender.
    function onBuy(Obligation memory, address buyer, uint256 buyerAssets, uint256, uint256, bytes memory data)
        external
    {
        require(msg.sender == MIDNIGHT, "unauthorized");
        bytes32 id = abi.decode(data, (bytes32));
        Obligation memory otherObligation = abi.decode(address(uint160(uint256(id))).code, (Obligation));
        Midnight(MIDNIGHT).withdraw(otherObligation, buyerAssets, buyer, buyer);
    }

    function onSell(Obligation memory, address, uint256, uint256, uint256, bytes memory) external pure {
        revert("not implemented");
    }

    function onLiquidate(Obligation memory, uint256, uint256, uint256, address, bytes memory) external pure {
        revert("not implemented");
    }
}
