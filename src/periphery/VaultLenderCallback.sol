// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {Market} from "../interfaces/IMidnight.sol";
import {IERC4626} from "./IERC4626.sol";
import {IERC20} from "./IERC20.sol";
import {IBuyCallback} from "../interfaces/ICallbacks.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";

contract VaultLenderCallback is IBuyCallback {
    address public immutable MIDNIGHT;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    /// @dev Callback to withdraw funds from an ERC4626 vault.
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
        address vault = abi.decode(data, (address));
        IERC4626(vault).withdraw(buyerAssets, address(this), buyer);
        IERC20(market.loanToken).approve(MIDNIGHT, buyerAssets);
        return CALLBACK_SUCCESS;
    }
}
