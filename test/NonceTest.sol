// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract NonceTest is BaseTest {
    function testSetNonceOk(address account, uint256 nonce1, uint256 nonce2) external {
        nonce1 = bound(nonce1, 0, type(uint248).max);
        nonce2 = bound(nonce2, nonce1, type(uint248).max);

        vm.prank(account);
        terms.setNonce(nonce1);

        assertEq(terms.nonce(account), nonce1, "nonce1");

        vm.prank(account);
        terms.setNonce(nonce2);
        assertEq(terms.nonce(account), nonce2, "nonce2");
    }

    function testSetNonceNoIncrease(address account, uint256 nonce1, uint256 nonce2) external {
        nonce1 = bound(nonce1, 1, type(uint248).max);
        nonce2 = bound(nonce2, 0, nonce1 - 1);

        vm.prank(account);
        terms.setNonce(nonce1);

        vm.prank(account);
        vm.expectRevert();
        terms.setNonce(nonce2);
    }
}
