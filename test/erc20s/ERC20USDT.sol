// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {PermitExt} from "./PermitExt.sol";

contract ERC20USDT is PermitExt {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name) PermitExt(_name) {}

    function _setAllowance(address owner, address spender, uint256 value) internal override {
        allowance[owner][spender] = value;
    }

    function _transfer(address _from, address _to, uint256 _amount) internal {
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;
    }

    function transfer(address _to, uint256 _amount) public {
        _transfer(msg.sender, _to, _amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount) public {
        if (allowance[_from][msg.sender] < type(uint256).max) {
            allowance[_from][msg.sender] -= _amount;
        }
        _transfer(_from, _to, _amount);
    }

    function approve(address _spender, uint256 _amount) public returns (bool) {
        require(!((_amount != 0) && (allowance[msg.sender][_spender] != 0)));

        allowance[msg.sender][_spender] = _amount;
        return true;
    }
}
