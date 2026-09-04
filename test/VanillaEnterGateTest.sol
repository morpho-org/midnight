// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {WhitelistEnterGate} from "../src/periphery/whitelist-enter-gate/WhitelistEnterGate.sol";
import {
    IWhitelistEnterGate,
    Mode,
    SET_IS_LISTED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "../src/periphery/whitelist-enter-gate/interfaces/IWhitelistEnterGate.sol";

bytes constant SET_IS_LISTED_TYPE =
    "SetIsListed(address whitelister,address account,bool newIsListed,uint256 nonce,uint256 deadline)";
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
        gate = _deploy(Mode.Whitelist, Mode.Whitelist);
    }

    function _deploy(Mode creditMode, Mode debtMode) internal returns (WhitelistEnterGate g) {
        g = new WhitelistEnterGate(roleSetter, creditMode, debtMode);
        vm.prank(roleSetter);
        g.setIsWhitelister(whitelister, true);
    }

    function _mode(uint8 raw) internal pure returns (Mode) {
        return Mode(bound(raw, 0, 2));
    }

    function _sign(address account, bool listed, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_LISTED_TYPEHASH, vm.addr(pk), account, listed, gate.nonces(vm.addr(pk), account), deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", gate.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(pk, digest);
    }

    function testSetIsListedTypeHash() public pure {
        assertEq(SET_IS_LISTED_TYPEHASH, keccak256(SET_IS_LISTED_TYPE));
    }

    function testEip712DomainTypeHash() public pure {
        assertEq(EIP712_DOMAIN_TYPEHASH, keccak256(EIP712_DOMAIN_TYPE));
    }

    function testDomainSeparator() public view {
        bytes32 expected = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(gate)));
        assertEq(gate.DOMAIN_SEPARATOR(), expected);
    }

    function testConstructor(address _roleSetter, uint8 rawCreditMode, uint8 rawDebtMode) public {
        Mode creditMode = _mode(rawCreditMode);
        Mode debtMode = _mode(rawDebtMode);
        vm.expectEmit();
        emit IWhitelistEnterGate.Constructor(_roleSetter, creditMode, debtMode);
        WhitelistEnterGate g = new WhitelistEnterGate(_roleSetter, creditMode, debtMode);
        assertEq(g.roleSetter(), _roleSetter);
        assertFalse(g.isWhitelister(_roleSetter));
        assertEq(uint256(g.CREDIT_MODE()), uint256(creditMode));
        assertEq(uint256(g.DEBT_MODE()), uint256(debtMode));
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

    function testSetIsListed(address account, bool listed) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsListed(whitelister, account, listed);
        vm.prank(whitelister);
        gate.setIsListed(account, listed);
        assertEq(gate.isListed(account), listed);
    }

    function testSetIsListedNotWhitelister(address caller, address account, bool listed) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setIsListed(account, listed);
    }

    function testRevokedWhitelisterCannotSetIsListed(address account) public {
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, false);

        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(whitelister);
        gate.setIsListed(account, true);
    }

    function testMultipleWhitelistersCanSetIsListed(address account, address account2) public {
        vm.assume(account != account2);

        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);

        vm.prank(whitelister);
        gate.setIsListed(account, true);
        vm.prank(whitelister2);
        gate.setIsListed(account2, true);

        assertTrue(gate.isListed(account));
        assertTrue(gate.isListed(account2));
    }

    function testCanIncreaseCreditWhitelistMode(address account, address other, uint8 rawDebtMode) public {
        vm.assume(account != other);
        gate = _deploy(Mode.Whitelist, _mode(rawDebtMode));
        vm.prank(whitelister);
        gate.setIsListed(account, true);
        assertTrue(gate.canIncreaseCredit(account));
        assertFalse(gate.canIncreaseCredit(other));
    }

    function testCanIncreaseCreditBlacklistMode(address account, address other, uint8 rawDebtMode) public {
        vm.assume(account != other);
        gate = _deploy(Mode.Blacklist, _mode(rawDebtMode));
        vm.prank(whitelister);
        gate.setIsListed(account, true);
        assertFalse(gate.canIncreaseCredit(account));
        assertTrue(gate.canIncreaseCredit(other));
    }

    function testCanIncreaseCreditOpenMode(address account, bool listed, uint8 rawDebtMode) public {
        gate = _deploy(Mode.Open, _mode(rawDebtMode));
        vm.prank(whitelister);
        gate.setIsListed(account, listed);
        assertTrue(gate.canIncreaseCredit(account));
    }

    function testCanIncreaseDebtWhitelistMode(address account, address other, uint8 rawCreditMode) public {
        vm.assume(account != other);
        gate = _deploy(_mode(rawCreditMode), Mode.Whitelist);
        vm.prank(whitelister);
        gate.setIsListed(account, true);
        assertTrue(gate.canIncreaseDebt(account));
        assertFalse(gate.canIncreaseDebt(other));
    }

    function testCanIncreaseDebtBlacklistMode(address account, address other, uint8 rawCreditMode) public {
        vm.assume(account != other);
        gate = _deploy(_mode(rawCreditMode), Mode.Blacklist);
        vm.prank(whitelister);
        gate.setIsListed(account, true);
        assertFalse(gate.canIncreaseDebt(account));
        assertTrue(gate.canIncreaseDebt(other));
    }

    function testCanIncreaseDebtOpenMode(address account, bool listed, uint8 rawCreditMode) public {
        gate = _deploy(_mode(rawCreditMode), Mode.Open);
        vm.prank(whitelister);
        gate.setIsListed(account, listed);
        assertTrue(gate.canIncreaseDebt(account));
    }

    function testBothSidesReadTheSameList(address account, bool listed) public {
        gate = _deploy(Mode.Whitelist, Mode.Blacklist);
        vm.prank(whitelister);
        gate.setIsListed(account, listed);
        assertEq(gate.canIncreaseCredit(account), listed);
        assertEq(gate.canIncreaseDebt(account), !listed);
    }

    function testSetIsListedWithSig(address account, bool listed, uint256 deadline, address relayer) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, listed, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsListedWithSig(whitelister, account, listed);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsListedWithSig(whitelister, account, listed, deadline, v, r, s);

        assertEq(gate.isListed(account), listed);
        assertEq(gate.nonces(whitelister, account), 1);
    }

    function testSetIsListedWithSigAcceptsAnyWhitelister(
        address account,
        bool listed,
        uint256 deadline,
        address relayer
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, listed, deadline, whitelister2Pk);

        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsListedWithSig(whitelister2, account, listed);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsListedWithSig(whitelister2, account, listed, deadline, v, r, s);

        assertEq(gate.isListed(account), listed);
        assertEq(gate.nonces(whitelister2, account), 1);
    }

    function testNoncesArePerWhitelister(address account, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);

        // Both whitelisters sign for the same account at their own nonce 0.
        (uint8 v1, bytes32 r1, bytes32 s1) = _sign(account, true, deadline, whitelisterPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _sign(account, true, deadline, whitelister2Pk);

        gate.setIsListedWithSig(whitelister, account, true, deadline, v1, r1, s1);
        gate.setIsListedWithSig(whitelister2, account, true, deadline, v2, r2, s2);

        assertEq(gate.nonces(whitelister, account), 1);
        assertEq(gate.nonces(whitelister2, account), 1);
    }

    function testSetIsListedWithSigRejectsRevokedWhitelister(address account, bool listed) public {
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, listed, deadline, whitelisterPk);

        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, false);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsListedWithSig(whitelister, account, listed, deadline, v, r, s);
    }

    function testSetIsListedWithSigRejectsReplayAndTampering() public {
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _sign(alice, true, deadline, whitelisterPk);
        gate.setIsListedWithSig(whitelister, alice, true, deadline, v, r, s);

        // replay
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsListedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong account
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsListedWithSig(whitelister, bob, false, deadline, v, r, s);

        // wrong value
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsListedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong deadline
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsListedWithSig(whitelister, alice, false, deadline + 1, v, r, s);

        // wrong whitelister
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsListedWithSig(whitelister2, alice, false, deadline, v, r, s);

        // wrong domain separator
        (v, r, s) = _sign(bob, true, deadline, whitelisterPk);
        WhitelistEnterGate otherGate = _deploy(Mode.Whitelist, Mode.Whitelist);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        otherGate.setIsListedWithSig(whitelister, bob, true, deadline, v, r, s);
    }

    function testSetIsListedWithSigDeadlineExpired(address account, bool listed, uint256 deadline, uint256 currentTime)
        public
    {
        deadline = bound(deadline, 0, type(uint256).max - 1);
        currentTime = bound(currentTime, deadline + 1, type(uint256).max);
        vm.warp(currentTime);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, listed, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistEnterGate.DeadlineExpired.selector);
        gate.setIsListedWithSig(whitelister, account, listed, deadline, v, r, s);
    }

    function testSetIsListedWithSigInvalidSigner(uint256 wrongPk, address account, bool listed, uint256 deadline)
        public
    {
        wrongPk = bound(wrongPk, 1, type(uint128).max);
        vm.assume(vm.addr(wrongPk) != whitelister);
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, listed, deadline, wrongPk);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsListedWithSig(vm.addr(wrongPk), account, listed, deadline, v, r, s);
    }

    function testSetIsListedWithSigEcrecoverReturnsZero(address account, bool listed, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (, bytes32 r, bytes32 s) = _sign(account, listed, deadline, whitelisterPk);

        // Invalid v (valid values are 27/28) -> ecrecover returns address(0).
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsListedWithSig(whitelister, account, listed, deadline, 0, r, s);
    }

    function testMulticall(address account, bool listed, address account2, bool listed2) public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IWhitelistEnterGate.setIsListed, (account, listed));
        data[1] = abi.encodeCall(IWhitelistEnterGate.setIsListed, (account2, listed2));

        vm.prank(whitelister);
        gate.multicall(data);

        if (account == account2) {
            assertEq(gate.isListed(account), listed2);
        } else {
            assertEq(gate.isListed(account), listed);
            assertEq(gate.isListed(account2), listed2);
        }
    }

    function testMulticallBubblesRevert(address caller, address account, bool listed) public {
        vm.assume(caller != whitelister);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(IWhitelistEnterGate.setIsListed, (account, listed));

        // Called by a non-whitelister: the inner call reverts and the multicall must bubble it up.
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.multicall(data);
    }
}
