// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";
import {PermitExt} from "./PermitExt.sol";

contract ERC20Permit is ERC20, PermitExt {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) PermitExt(_name) {}

    function _setAllowance(address owner, address spender, uint256 value) internal override {
        allowance[owner][spender] = value;
    }
}
