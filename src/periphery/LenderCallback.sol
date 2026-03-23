// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.31;

import {Obligation} from "../interfaces/IMidnight.sol";
import {Midnight} from "../Midnight.sol";
import {IERC4626} from "./IERC4626.sol";

enum WithdrawType {
    VaultV2,
    Midnight
    // VaultV1?
}

contract LenderCallback {
    address public immutable midnight;

    constructor(address _midnight) {
        midnight = _midnight;
    }

    /// @dev Callback to withdraw funds on behalf of lender.
    /// @dev The callback contract should be authorized to withdraw funds on behalf of the lender.
    function onBuy(
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 units,
        bytes memory data
    ) external {
        require(msg.sender == midnight, "unauthorized");
        (bytes32 withdrawData, WithdrawType withdrawType) = abi.decode(data, (bytes32, WithdrawType));

        if (withdrawType == WithdrawType.VaultV2) {
            address vault = address(bytes20(withdrawData));
            IERC4626(vault).withdraw(buyerAssets, buyer, buyer);
        } else if (withdrawType == WithdrawType.Midnight) {
            address obligationDataAddress = address(uint160(uint256(withdrawData)));
            Obligation memory otherObligation = abi.decode(obligationDataAddress.code, (Obligation));
            Midnight(midnight).withdraw(otherObligation, buyerAssets, buyer, buyer);
        }
    }

    function onSell(
        Obligation memory obligation,
        address seller,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 units,
        bytes memory data
    ) external {
        revert("not implemented");
    }

    function onLiquidate(
        Obligation memory obligation,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address borrower,
        bytes memory data
    ) external {
        revert("not implemented");
    }
}
