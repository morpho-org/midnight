// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {Obligation} from "../interfaces/IMidnight.sol";
import {IERC4626} from "./IERC4626.sol";
import {IERC20} from "./IERC20.sol";
import {ICallbacks} from "../interfaces/ICallbacks.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";

contract VaultLenderCallback is ICallbacks {
    address public immutable MIDNIGHT;

    constructor(address _midnight) {
        MIDNIGHT = _midnight;
    }

    /// @dev Callback to withdraw funds from an ERC4626 vault.
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
        address vault = abi.decode(data, (address));
        IERC4626(vault).withdraw(buyerAssets, address(this), buyer);
        IERC20(obligation.loanToken).approve(MIDNIGHT, buyerAssets);
        return CALLBACK_SUCCESS;
    }

    function onSell(bytes32, Obligation memory, address, uint256, uint256, bytes memory)
        external
        pure
        returns (bytes32)
    {
        revert("not implemented");
    }

    function onLiquidate(bytes32, Obligation memory, uint256, uint256, uint256, address, bytes memory) external pure {
        revert("not implemented");
    }

    function onRepay(bytes32, Obligation memory, uint256, address, bytes memory) external pure {
        revert("not implemented");
    }
}
