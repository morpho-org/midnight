// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {PermitExt} from "./PermitExt.sol";

contract ERC20RevertToZero is PermitExt {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name) PermitExt(_name) {}

    function _setAllowance(address owner, address spender, uint256 value) internal override {
        allowance[owner][spender] = value;
    }

    function _transfer(address _from, address _to, uint256 _amount) internal returns (bool) {
        require(_to != address(0), "ERC20: transfer to the zero address");
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;
        return true;
    }

    function transfer(address _to, uint256 _amount) public returns (bool) {
        return _transfer(msg.sender, _to, _amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount) public returns (bool) {
        allowance[_from][msg.sender] -= _amount;
        return _transfer(_from, _to, _amount);
    }

    function approve(address _spender, uint256 _amount) public returns (bool) {
        allowance[msg.sender][_spender] = _amount;
        return true;
    }
}
