// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {Obligation} from "../interfaces/IMidnight.sol";
import {Midnight} from "../Midnight.sol";
import {IERC4626} from "./IERC4626.sol";
import {ICallbacks} from "../interfaces/ICallbacks.sol";

enum WithdrawType {
    VaultV2,
    Midnight
    // VaultV1?
}

contract LenderCallback is ICallbacks {
    address public immutable MIDNIGHT;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    /// @dev Callback to withdraw funds on behalf of lender.
    /// @dev The callback contract should be authorized to withdraw funds on behalf of the lender.
    function onBuy(Obligation memory, address buyer, uint256 buyerAssets, uint256, uint256, bytes memory data)
        external
    {
        require(msg.sender == MIDNIGHT, "unauthorized");
        (bytes32 withdrawData, WithdrawType withdrawType) = abi.decode(data, (bytes32, WithdrawType));

        if (withdrawType == WithdrawType.VaultV2) {
            address vault = address(uint160(uint256(withdrawData)));
            IERC4626(vault).withdraw(buyerAssets, buyer, buyer);
        } else if (withdrawType == WithdrawType.Midnight) {
            address obligationDataAddress = address(uint160(uint256(withdrawData)));
            Obligation memory otherObligation = abi.decode(obligationDataAddress.code, (Obligation));
            Midnight(MIDNIGHT).withdraw(otherObligation, buyerAssets, buyer, buyer);
        }
    }

    function onSell(Obligation memory, address, uint256, uint256, uint256, bytes memory) external pure {
        revert("not implemented");
    }

    function onLiquidate(Obligation memory, uint256, uint256, uint256, address, bytes memory) external pure {
        revert("not implemented");
    }
}
