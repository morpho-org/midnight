// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

contract ERC20 {
    string public name;
    string public symbol;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function transfer(address receiver, uint256 amount) public returns (bool) {
        require(amount <= balanceOf[msg.sender], "Insufficient balance");

        balanceOf[msg.sender] -= amount;
        balanceOf[receiver] += amount;

        return true;
    }

    function transferFrom(address sender, address receiver, uint256 amount) public returns (bool) {
        require(amount <= balanceOf[sender], "Insufficient balance");
        require(amount <= allowance[sender][msg.sender], "Insufficient allowance");

        balanceOf[sender] -= amount;
        balanceOf[receiver] += amount;
        allowance[sender][msg.sender] -= amount;

        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}
