// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {WhitelistEnterGate} from "../src/periphery/whitelist-enter-gate/WhitelistEnterGate.sol";
import {
    IWhitelistEnterGate,
    SET_IS_WHITELISTED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "../src/periphery/whitelist-enter-gate/interfaces/IWhitelistEnterGate.sol";

bytes constant SET_IS_WHITELISTED_TYPE =
    "SetIsWhitelisted(address whitelister,address account,bool newIsWhitelisted,uint256 nonce,uint256 deadline)";
bytes constant EIP712_DOMAIN_TYPE = "EIP712Domain(uint256 chainId,address verifyingContract)";

contract WhitelistEnterGateTest is Test {
    WhitelistEnterGate internal gate;
    uint256 internal whitelisterPk;
    uint256 internal whitelister2Pk;
    address internal roleSetter = makeAddr("roleSetter");
    address internal whitelister;
    address internal whitelister2;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        whitelisterPk = 0xA11CE;
        whitelister2Pk = 0xB0B;
        whitelister = vm.addr(whitelisterPk);
        whitelister2 = vm.addr(whitelister2Pk);
        gate = new WhitelistEnterGate(roleSetter);
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, true);
    }

    function _sign(address account, bool whitelisted, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_WHITELISTED_TYPEHASH,
                vm.addr(pk),
                account,
                whitelisted,
                gate.nonces(vm.addr(pk), account),
                deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", gate.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(pk, digest);
    }

    function testSetIsWhitelistedTypeHash() public pure {
        assertEq(SET_IS_WHITELISTED_TYPEHASH, keccak256(SET_IS_WHITELISTED_TYPE));
    }

    function testEip712DomainTypeHash() public pure {
        assertEq(EIP712_DOMAIN_TYPEHASH, keccak256(EIP712_DOMAIN_TYPE));
    }

    function testDomainSeparator() public view {
        bytes32 expected = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(gate)));
        assertEq(gate.DOMAIN_SEPARATOR(), expected);
    }

    function testConstructor(address _roleSetter) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.Constructor(_roleSetter);
        WhitelistEnterGate g = new WhitelistEnterGate(_roleSetter);
        assertEq(g.roleSetter(), _roleSetter);
        assertFalse(g.isWhitelister(_roleSetter));
    }

    function testSetRoleSetter(address newRoleSetter) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetRoleSetter(newRoleSetter);
        vm.prank(roleSetter);
        gate.setRoleSetter(newRoleSetter);
        assertEq(gate.roleSetter(), newRoleSetter);
    }

    function testSetRoleSetterNotRoleSetter(address caller, address newRoleSetter) public {
        vm.assume(caller != roleSetter);
        vm.expectRevert(IWhitelistEnterGate.NotRoleSetter.selector);
        vm.prank(caller);
        gate.setRoleSetter(newRoleSetter);
    }

    function testSetIsWhitelister(address account, bool isWhitelister_) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsWhitelister(account, isWhitelister_);
        vm.prank(roleSetter);
        gate.setIsWhitelister(account, isWhitelister_);
        assertEq(gate.isWhitelister(account), isWhitelister_);
    }

    function testSetIsWhitelisterNotRoleSetter(address caller, address account, bool isWhitelister_) public {
        vm.assume(caller != roleSetter);
        vm.expectRevert(IWhitelistEnterGate.NotRoleSetter.selector);
        vm.prank(caller);
        gate.setIsWhitelister(account, isWhitelister_);
    }

    function testWhitelisterCannotSetIsWhitelister(address account, bool isWhitelister_) public {
        vm.expectRevert(IWhitelistEnterGate.NotRoleSetter.selector);
        vm.prank(whitelister);
        gate.setIsWhitelister(account, isWhitelister_);
    }

    function testMultipleWhitelistersCanSetIsWhitelisted(address account, address account2) public {
        vm.assume(account != account2);

        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);

        vm.prank(whitelister);
        gate.setIsWhitelisted(account, true);
        vm.prank(whitelister2);
        gate.setIsWhitelisted(account2, true);

        assertTrue(gate.isWhitelisted(account));
        assertTrue(gate.isWhitelisted(account2));
    }

    function testRevokedWhitelisterCannotSetIsWhitelisted(address account) public {
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, false);

        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(whitelister);
        gate.setIsWhitelisted(account, true);
    }

    function testSetIsWhitelisted(address account, bool whitelisted) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsWhitelisted(whitelister, account, whitelisted);
        vm.prank(whitelister);
        gate.setIsWhitelisted(account, whitelisted);
        assertEq(gate.isWhitelisted(account), whitelisted);
    }

    function testSetIsWhitelistedNotWhitelister(address caller, address account, bool whitelisted) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setIsWhitelisted(account, whitelisted);
    }

    function testCanIncreaseCredit(address account, address other) public {
        vm.assume(account != other);
        vm.prank(whitelister);
        gate.setIsWhitelisted(account, true);
        assertTrue(gate.canIncreaseCredit(account));
        assertFalse(gate.canIncreaseCredit(other));
    }

    function testCanIncreaseDebt(address account, address other) public {
        vm.assume(account != other);
        vm.prank(whitelister);
        gate.setIsWhitelisted(account, true);
        assertTrue(gate.canIncreaseDebt(account));
        assertFalse(gate.canIncreaseDebt(other));
    }

    function testSetIsWhitelistedWithSig(address account, bool whitelisted, uint256 deadline, address relayer) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsWhitelistedWithSig(whitelister, account, whitelisted);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsWhitelistedWithSig(whitelister, account, whitelisted, deadline, v, r, s);

        assertEq(gate.isWhitelisted(account), whitelisted);
        assertEq(gate.nonces(whitelister, account), 1);
    }

    function testSetIsWhitelistedWithSigAcceptsAnyWhitelister(
        address account,
        bool whitelisted,
        uint256 deadline,
        address relayer
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, whitelister2Pk);

        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsWhitelistedWithSig(whitelister2, account, whitelisted);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsWhitelistedWithSig(whitelister2, account, whitelisted, deadline, v, r, s);

        assertEq(gate.isWhitelisted(account), whitelisted);
        assertEq(gate.nonces(whitelister2, account), 1);
    }

    function testNoncesArePerWhitelister(address account, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);

        // Both whitelisters sign for the same account at their own nonce 0.
        (uint8 v1, bytes32 r1, bytes32 s1) = _sign(account, true, deadline, whitelisterPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _sign(account, true, deadline, whitelister2Pk);

        gate.setIsWhitelistedWithSig(whitelister, account, true, deadline, v1, r1, s1);
        gate.setIsWhitelistedWithSig(whitelister2, account, true, deadline, v2, r2, s2);

        assertEq(gate.nonces(whitelister, account), 1);
        assertEq(gate.nonces(whitelister2, account), 1);
    }

    function testSetIsWhitelistedWithSigRejectsRevokedWhitelister(address account, bool whitelisted) public {
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, whitelisterPk);

        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, false);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, account, whitelisted, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigRejectsReplayAndTampering() public {
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _sign(alice, true, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // replay
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong account
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, bob, false, deadline, v, r, s);

        // wrong value
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong deadline
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, alice, false, deadline + 1, v, r, s);

        // wrong whitelister
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister2, alice, false, deadline, v, r, s);

        // wrong domain separator
        (v, r, s) = _sign(bob, true, deadline, whitelisterPk);
        WhitelistEnterGate otherGate = new WhitelistEnterGate(roleSetter);
        vm.prank(roleSetter);
        otherGate.setIsWhitelister(whitelister, true);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        otherGate.setIsWhitelistedWithSig(whitelister, bob, true, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigDeadlineExpired(
        address account,
        bool whitelisted,
        uint256 deadline,
        uint256 currentTime
    ) public {
        deadline = bound(deadline, 0, type(uint256).max - 1);
        currentTime = bound(currentTime, deadline + 1, type(uint256).max);
        vm.warp(currentTime);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistEnterGate.DeadlineExpired.selector);
        gate.setIsWhitelistedWithSig(whitelister, account, whitelisted, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigInvalidSigner(
        uint256 wrongPk,
        address account,
        bool whitelisted,
        uint256 deadline
    ) public {
        wrongPk = bound(wrongPk, 1, type(uint128).max);
        vm.assume(vm.addr(wrongPk) != whitelister);
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, wrongPk);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(vm.addr(wrongPk), account, whitelisted, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigEcrecoverReturnsZero(address account, bool whitelisted, uint256 deadline)
        public
    {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, whitelisterPk);

        // Invalid v (valid values are 27/28) -> ecrecover returns address(0).
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, account, whitelisted, deadline, 0, r, s);
    }

    function testMulticall(address account, bool whitelisted, address account2, bool whitelisted2) public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IWhitelistEnterGate.setIsWhitelisted, (account, whitelisted));
        data[1] = abi.encodeCall(IWhitelistEnterGate.setIsWhitelisted, (account2, whitelisted2));

        vm.prank(whitelister);
        gate.multicall(data);

        if (account == account2) {
            assertEq(gate.isWhitelisted(account), whitelisted2);
        } else {
            assertEq(gate.isWhitelisted(account), whitelisted);
            assertEq(gate.isWhitelisted(account2), whitelisted2);
        }
    }

    function testMulticallBubblesRevert(address caller, address account, bool whitelisted) public {
        vm.assume(caller != whitelister);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(IWhitelistEnterGate.setIsWhitelisted, (account, whitelisted));

        // Called by a non-whitelister: the inner call reverts and the multicall must bubble it up.
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.multicall(data);
    }
}
