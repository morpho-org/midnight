// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {WhitelistEnterGate} from "../src/periphery/whitelist-enter-gate/WhitelistEnterGate.sol";
import {
    IWhitelistEnterGate,
    Mode,
    SET_IS_CREDIT_WHITELISTED_TYPEHASH,
    SET_IS_CREDIT_BLACKLISTED_TYPEHASH,
    SET_IS_DEBT_WHITELISTED_TYPEHASH,
    SET_IS_DEBT_BLACKLISTED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "../src/periphery/whitelist-enter-gate/interfaces/IWhitelistEnterGate.sol";

bytes constant SET_IS_CREDIT_WHITELISTED_TYPE =
    "SetIsCreditWhitelisted(address whitelister,address account,bool newIsCreditWhitelisted,uint256 nonce,uint256 deadline)";
bytes constant SET_IS_CREDIT_BLACKLISTED_TYPE =
    "SetIsCreditBlacklisted(address whitelister,address account,bool newIsCreditBlacklisted,uint256 nonce,uint256 deadline)";
bytes constant SET_IS_DEBT_WHITELISTED_TYPE =
    "SetIsDebtWhitelisted(address whitelister,address account,bool newIsDebtWhitelisted,uint256 nonce,uint256 deadline)";
bytes constant SET_IS_DEBT_BLACKLISTED_TYPE =
    "SetIsDebtBlacklisted(address whitelister,address account,bool newIsDebtBlacklisted,uint256 nonce,uint256 deadline)";
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

    function _signCreditWhitelisted(address account, bool listed, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_CREDIT_WHITELISTED_TYPEHASH,
                vm.addr(pk),
                account,
                listed,
                gate.nonces(vm.addr(pk), account),
                deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", gate.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(pk, digest);
    }

    function _signCreditBlacklisted(address account, bool listed, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_CREDIT_BLACKLISTED_TYPEHASH,
                vm.addr(pk),
                account,
                listed,
                gate.nonces(vm.addr(pk), account),
                deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", gate.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(pk, digest);
    }

    function _signDebtWhitelisted(address account, bool listed, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_DEBT_WHITELISTED_TYPEHASH,
                vm.addr(pk),
                account,
                listed,
                gate.nonces(vm.addr(pk), account),
                deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", gate.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(pk, digest);
    }

    function _signDebtBlacklisted(address account, bool listed, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_DEBT_BLACKLISTED_TYPEHASH,
                vm.addr(pk),
                account,
                listed,
                gate.nonces(vm.addr(pk), account),
                deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", gate.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(pk, digest);
    }

    function testSetIsCreditWhitelistedTypeHash() public pure {
        assertEq(SET_IS_CREDIT_WHITELISTED_TYPEHASH, keccak256(SET_IS_CREDIT_WHITELISTED_TYPE));
    }

    function testSetIsCreditBlacklistedTypeHash() public pure {
        assertEq(SET_IS_CREDIT_BLACKLISTED_TYPEHASH, keccak256(SET_IS_CREDIT_BLACKLISTED_TYPE));
    }

    function testSetIsDebtWhitelistedTypeHash() public pure {
        assertEq(SET_IS_DEBT_WHITELISTED_TYPEHASH, keccak256(SET_IS_DEBT_WHITELISTED_TYPE));
    }

    function testSetIsDebtBlacklistedTypeHash() public pure {
        assertEq(SET_IS_DEBT_BLACKLISTED_TYPEHASH, keccak256(SET_IS_DEBT_BLACKLISTED_TYPE));
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

    function testSetIsCreditWhitelisted(address account, bool listed) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsCreditWhitelisted(whitelister, account, listed);
        vm.prank(whitelister);
        gate.setIsCreditWhitelisted(account, listed);
        assertEq(gate.isCreditWhitelisted(account), listed);
        assertFalse(gate.isCreditBlacklisted(account));
        assertFalse(gate.isDebtWhitelisted(account));
        assertFalse(gate.isDebtBlacklisted(account));
    }

    function testSetIsCreditWhitelistedNotWhitelister(address caller, address account, bool listed) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setIsCreditWhitelisted(account, listed);
    }

    function testSetIsCreditBlacklisted(address account, bool listed) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsCreditBlacklisted(whitelister, account, listed);
        vm.prank(whitelister);
        gate.setIsCreditBlacklisted(account, listed);
        assertEq(gate.isCreditBlacklisted(account), listed);
        assertFalse(gate.isCreditWhitelisted(account));
        assertFalse(gate.isDebtWhitelisted(account));
        assertFalse(gate.isDebtBlacklisted(account));
    }

    function testSetIsCreditBlacklistedNotWhitelister(address caller, address account, bool listed) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setIsCreditBlacklisted(account, listed);
    }

    function testSetIsDebtWhitelisted(address account, bool listed) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsDebtWhitelisted(whitelister, account, listed);
        vm.prank(whitelister);
        gate.setIsDebtWhitelisted(account, listed);
        assertEq(gate.isDebtWhitelisted(account), listed);
        assertFalse(gate.isCreditWhitelisted(account));
        assertFalse(gate.isCreditBlacklisted(account));
        assertFalse(gate.isDebtBlacklisted(account));
    }

    function testSetIsDebtWhitelistedNotWhitelister(address caller, address account, bool listed) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setIsDebtWhitelisted(account, listed);
    }

    function testSetIsDebtBlacklisted(address account, bool listed) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsDebtBlacklisted(whitelister, account, listed);
        vm.prank(whitelister);
        gate.setIsDebtBlacklisted(account, listed);
        assertEq(gate.isDebtBlacklisted(account), listed);
        assertFalse(gate.isCreditWhitelisted(account));
        assertFalse(gate.isCreditBlacklisted(account));
        assertFalse(gate.isDebtWhitelisted(account));
    }

    function testSetIsDebtBlacklistedNotWhitelister(address caller, address account, bool listed) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setIsDebtBlacklisted(account, listed);
    }

    function testRevokedWhitelisterCannotSetLists(address account) public {
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, false);

        vm.startPrank(whitelister);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        gate.setIsCreditWhitelisted(account, true);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        gate.setIsCreditBlacklisted(account, true);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        gate.setIsDebtWhitelisted(account, true);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        gate.setIsDebtBlacklisted(account, true);
        vm.stopPrank();
    }

    function testMultipleWhitelistersCanSetLists(address account, address account2) public {
        vm.assume(account != account2);

        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);

        vm.startPrank(whitelister);
        gate.setIsCreditWhitelisted(account, true);
        gate.setIsCreditBlacklisted(account, true);
        gate.setIsDebtWhitelisted(account, true);
        gate.setIsDebtBlacklisted(account, true);
        vm.stopPrank();
        vm.startPrank(whitelister2);
        gate.setIsCreditWhitelisted(account2, true);
        gate.setIsCreditBlacklisted(account2, true);
        gate.setIsDebtWhitelisted(account2, true);
        gate.setIsDebtBlacklisted(account2, true);
        vm.stopPrank();

        assertTrue(gate.isCreditWhitelisted(account));
        assertTrue(gate.isCreditWhitelisted(account2));
        assertTrue(gate.isCreditBlacklisted(account));
        assertTrue(gate.isCreditBlacklisted(account2));
        assertTrue(gate.isDebtWhitelisted(account));
        assertTrue(gate.isDebtWhitelisted(account2));
        assertTrue(gate.isDebtBlacklisted(account));
        assertTrue(gate.isDebtBlacklisted(account2));
    }

    function testCanIncreaseCreditWhitelistMode(address account, address other) public {
        vm.assume(account != other);
        vm.startPrank(whitelister);
        gate.setIsCreditWhitelisted(account, true);
        gate.setIsCreditBlacklisted(account, true);
        gate.setIsCreditBlacklisted(other, true);
        vm.stopPrank();
        assertTrue(gate.canIncreaseCredit(account));
        assertFalse(gate.canIncreaseCredit(other));
        assertFalse(gate.canIncreaseDebt(account));
    }

    function testCanIncreaseCreditBlacklistMode(address account, address other) public {
        vm.assume(account != other);
        WhitelistEnterGate g = _deploy(Mode.Blacklist, Mode.Whitelist);
        vm.startPrank(whitelister);
        g.setIsCreditBlacklisted(account, true);
        g.setIsCreditWhitelisted(account, true);
        vm.stopPrank();
        assertFalse(g.canIncreaseCredit(account));
        assertTrue(g.canIncreaseCredit(other));
        assertFalse(g.canIncreaseDebt(other));
    }

    function testCanIncreaseCreditOpenMode(address account, bool whitelisted, bool blacklisted) public {
        WhitelistEnterGate g = _deploy(Mode.Open, Mode.Whitelist);
        vm.startPrank(whitelister);
        g.setIsCreditWhitelisted(account, whitelisted);
        g.setIsCreditBlacklisted(account, blacklisted);
        vm.stopPrank();
        assertTrue(g.canIncreaseCredit(account));
        assertFalse(g.canIncreaseDebt(account));
    }

    function testCanIncreaseDebtWhitelistMode(address account, address other) public {
        vm.assume(account != other);
        vm.startPrank(whitelister);
        gate.setIsDebtWhitelisted(account, true);
        gate.setIsDebtBlacklisted(account, true);
        gate.setIsDebtBlacklisted(other, true);
        vm.stopPrank();
        assertTrue(gate.canIncreaseDebt(account));
        assertFalse(gate.canIncreaseDebt(other));
        assertFalse(gate.canIncreaseCredit(account));
    }

    function testCanIncreaseDebtBlacklistMode(address account, address other) public {
        vm.assume(account != other);
        WhitelistEnterGate g = _deploy(Mode.Whitelist, Mode.Blacklist);
        vm.startPrank(whitelister);
        g.setIsDebtBlacklisted(account, true);
        g.setIsDebtWhitelisted(account, true);
        vm.stopPrank();
        assertFalse(g.canIncreaseDebt(account));
        assertTrue(g.canIncreaseDebt(other));
        assertFalse(g.canIncreaseCredit(other));
    }

    function testCanIncreaseDebtOpenMode(address account, bool whitelisted, bool blacklisted) public {
        WhitelistEnterGate g = _deploy(Mode.Whitelist, Mode.Open);
        vm.startPrank(whitelister);
        g.setIsDebtWhitelisted(account, whitelisted);
        g.setIsDebtBlacklisted(account, blacklisted);
        vm.stopPrank();
        assertTrue(g.canIncreaseDebt(account));
        assertFalse(g.canIncreaseCredit(account));
    }

    function testSetIsCreditWhitelistedWithSig(address account, bool listed, uint256 deadline, address relayer) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _signCreditWhitelisted(account, listed, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsCreditWhitelistedWithSig(whitelister, account, listed);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsCreditWhitelistedWithSig(whitelister, account, listed, deadline, v, r, s);

        assertEq(gate.isCreditWhitelisted(account), listed);
        assertFalse(gate.isCreditBlacklisted(account));
        assertFalse(gate.isDebtWhitelisted(account));
        assertFalse(gate.isDebtBlacklisted(account));
        assertEq(gate.nonces(whitelister, account), 1);
    }

    function testSetIsCreditWhitelistedWithSigRejectsOtherLists(address account, bool listed, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _signCreditWhitelisted(account, listed, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditBlacklistedWithSig(whitelister, account, listed, deadline, v, r, s);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtWhitelistedWithSig(whitelister, account, listed, deadline, v, r, s);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtBlacklistedWithSig(whitelister, account, listed, deadline, v, r, s);
    }

    function testSetIsCreditWhitelistedWithSigRejectsReplayAndTampering() public {
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _signCreditWhitelisted(alice, true, deadline, whitelisterPk);
        gate.setIsCreditWhitelistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // replay
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditWhitelistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong account
        (v, r, s) = _signCreditWhitelisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditWhitelistedWithSig(whitelister, bob, false, deadline, v, r, s);

        // wrong value
        (v, r, s) = _signCreditWhitelisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditWhitelistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong deadline
        (v, r, s) = _signCreditWhitelisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditWhitelistedWithSig(whitelister, alice, false, deadline + 1, v, r, s);

        // wrong whitelister
        (v, r, s) = _signCreditWhitelisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditWhitelistedWithSig(whitelister2, alice, false, deadline, v, r, s);

        // wrong domain separator
        (v, r, s) = _signCreditWhitelisted(bob, true, deadline, whitelisterPk);
        WhitelistEnterGate otherGate = _deploy(Mode.Whitelist, Mode.Whitelist);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        otherGate.setIsCreditWhitelistedWithSig(whitelister, bob, true, deadline, v, r, s);
    }

    function testSetIsCreditBlacklistedWithSig(address account, bool listed, uint256 deadline, address relayer) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _signCreditBlacklisted(account, listed, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsCreditBlacklistedWithSig(whitelister, account, listed);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsCreditBlacklistedWithSig(whitelister, account, listed, deadline, v, r, s);

        assertEq(gate.isCreditBlacklisted(account), listed);
        assertFalse(gate.isCreditWhitelisted(account));
        assertFalse(gate.isDebtWhitelisted(account));
        assertFalse(gate.isDebtBlacklisted(account));
        assertEq(gate.nonces(whitelister, account), 1);
    }

    function testSetIsCreditBlacklistedWithSigRejectsOtherLists(address account, bool listed, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _signCreditBlacklisted(account, listed, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditWhitelistedWithSig(whitelister, account, listed, deadline, v, r, s);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtWhitelistedWithSig(whitelister, account, listed, deadline, v, r, s);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtBlacklistedWithSig(whitelister, account, listed, deadline, v, r, s);
    }

    function testSetIsCreditBlacklistedWithSigRejectsReplayAndTampering() public {
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _signCreditBlacklisted(alice, true, deadline, whitelisterPk);
        gate.setIsCreditBlacklistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // replay
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditBlacklistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong account
        (v, r, s) = _signCreditBlacklisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditBlacklistedWithSig(whitelister, bob, false, deadline, v, r, s);

        // wrong value
        (v, r, s) = _signCreditBlacklisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditBlacklistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong deadline
        (v, r, s) = _signCreditBlacklisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditBlacklistedWithSig(whitelister, alice, false, deadline + 1, v, r, s);

        // wrong whitelister
        (v, r, s) = _signCreditBlacklisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditBlacklistedWithSig(whitelister2, alice, false, deadline, v, r, s);

        // wrong domain separator
        (v, r, s) = _signCreditBlacklisted(bob, true, deadline, whitelisterPk);
        WhitelistEnterGate otherGate = _deploy(Mode.Whitelist, Mode.Whitelist);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        otherGate.setIsCreditBlacklistedWithSig(whitelister, bob, true, deadline, v, r, s);
    }

    function testSetIsDebtWhitelistedWithSig(address account, bool listed, uint256 deadline, address relayer) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _signDebtWhitelisted(account, listed, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsDebtWhitelistedWithSig(whitelister, account, listed);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsDebtWhitelistedWithSig(whitelister, account, listed, deadline, v, r, s);

        assertEq(gate.isDebtWhitelisted(account), listed);
        assertFalse(gate.isCreditWhitelisted(account));
        assertFalse(gate.isCreditBlacklisted(account));
        assertFalse(gate.isDebtBlacklisted(account));
        assertEq(gate.nonces(whitelister, account), 1);
    }

    function testSetIsDebtWhitelistedWithSigRejectsOtherLists(address account, bool listed, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _signDebtWhitelisted(account, listed, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditWhitelistedWithSig(whitelister, account, listed, deadline, v, r, s);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditBlacklistedWithSig(whitelister, account, listed, deadline, v, r, s);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtBlacklistedWithSig(whitelister, account, listed, deadline, v, r, s);
    }

    function testSetIsDebtWhitelistedWithSigRejectsReplayAndTampering() public {
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _signDebtWhitelisted(alice, true, deadline, whitelisterPk);
        gate.setIsDebtWhitelistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // replay
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtWhitelistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong account
        (v, r, s) = _signDebtWhitelisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtWhitelistedWithSig(whitelister, bob, false, deadline, v, r, s);

        // wrong value
        (v, r, s) = _signDebtWhitelisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtWhitelistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong deadline
        (v, r, s) = _signDebtWhitelisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtWhitelistedWithSig(whitelister, alice, false, deadline + 1, v, r, s);

        // wrong whitelister
        (v, r, s) = _signDebtWhitelisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtWhitelistedWithSig(whitelister2, alice, false, deadline, v, r, s);

        // wrong domain separator
        (v, r, s) = _signDebtWhitelisted(bob, true, deadline, whitelisterPk);
        WhitelistEnterGate otherGate = _deploy(Mode.Whitelist, Mode.Whitelist);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        otherGate.setIsDebtWhitelistedWithSig(whitelister, bob, true, deadline, v, r, s);
    }

    function testSetIsDebtBlacklistedWithSig(address account, bool listed, uint256 deadline, address relayer) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _signDebtBlacklisted(account, listed, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsDebtBlacklistedWithSig(whitelister, account, listed);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsDebtBlacklistedWithSig(whitelister, account, listed, deadline, v, r, s);

        assertEq(gate.isDebtBlacklisted(account), listed);
        assertFalse(gate.isCreditWhitelisted(account));
        assertFalse(gate.isCreditBlacklisted(account));
        assertFalse(gate.isDebtWhitelisted(account));
        assertEq(gate.nonces(whitelister, account), 1);
    }

    function testSetIsDebtBlacklistedWithSigRejectsOtherLists(address account, bool listed, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _signDebtBlacklisted(account, listed, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditWhitelistedWithSig(whitelister, account, listed, deadline, v, r, s);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditBlacklistedWithSig(whitelister, account, listed, deadline, v, r, s);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtWhitelistedWithSig(whitelister, account, listed, deadline, v, r, s);
    }

    function testSetIsDebtBlacklistedWithSigRejectsReplayAndTampering() public {
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _signDebtBlacklisted(alice, true, deadline, whitelisterPk);
        gate.setIsDebtBlacklistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // replay
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtBlacklistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong account
        (v, r, s) = _signDebtBlacklisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtBlacklistedWithSig(whitelister, bob, false, deadline, v, r, s);

        // wrong value
        (v, r, s) = _signDebtBlacklisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtBlacklistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong deadline
        (v, r, s) = _signDebtBlacklisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtBlacklistedWithSig(whitelister, alice, false, deadline + 1, v, r, s);

        // wrong whitelister
        (v, r, s) = _signDebtBlacklisted(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtBlacklistedWithSig(whitelister2, alice, false, deadline, v, r, s);

        // wrong domain separator
        (v, r, s) = _signDebtBlacklisted(bob, true, deadline, whitelisterPk);
        WhitelistEnterGate otherGate = _deploy(Mode.Whitelist, Mode.Whitelist);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        otherGate.setIsDebtBlacklistedWithSig(whitelister, bob, true, deadline, v, r, s);
    }

    function testSetListsWithSigAcceptsAnyWhitelister(address account, bool listed, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);
        uint8 v;
        bytes32 r;
        bytes32 s;

        (v, r, s) = _signCreditWhitelisted(account, listed, deadline, whitelister2Pk);
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsCreditWhitelistedWithSig(whitelister2, account, listed);
        gate.setIsCreditWhitelistedWithSig(whitelister2, account, listed, deadline, v, r, s);
        assertEq(gate.isCreditWhitelisted(account), listed);

        (v, r, s) = _signCreditBlacklisted(account, listed, deadline, whitelister2Pk);
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsCreditBlacklistedWithSig(whitelister2, account, listed);
        gate.setIsCreditBlacklistedWithSig(whitelister2, account, listed, deadline, v, r, s);
        assertEq(gate.isCreditBlacklisted(account), listed);

        (v, r, s) = _signDebtWhitelisted(account, listed, deadline, whitelister2Pk);
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsDebtWhitelistedWithSig(whitelister2, account, listed);
        gate.setIsDebtWhitelistedWithSig(whitelister2, account, listed, deadline, v, r, s);
        assertEq(gate.isDebtWhitelisted(account), listed);

        (v, r, s) = _signDebtBlacklisted(account, listed, deadline, whitelister2Pk);
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsDebtBlacklistedWithSig(whitelister2, account, listed);
        gate.setIsDebtBlacklistedWithSig(whitelister2, account, listed, deadline, v, r, s);
        assertEq(gate.isDebtBlacklisted(account), listed);

        assertEq(gate.nonces(whitelister2, account), 4);
    }

    function testNoncesArePerWhitelister(address account, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);

        // Both whitelisters sign for the same account at their own nonce 0.
        (uint8 v1, bytes32 r1, bytes32 s1) = _signCreditWhitelisted(account, true, deadline, whitelisterPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _signCreditWhitelisted(account, true, deadline, whitelister2Pk);

        gate.setIsCreditWhitelistedWithSig(whitelister, account, true, deadline, v1, r1, s1);
        gate.setIsCreditWhitelistedWithSig(whitelister2, account, true, deadline, v2, r2, s2);

        assertEq(gate.nonces(whitelister, account), 1);
        assertEq(gate.nonces(whitelister2, account), 1);
    }

    function testNoncesAreSharedByAllLists(address account, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        uint8 v;
        bytes32 r;
        bytes32 s;

        (v, r, s) = _signCreditWhitelisted(account, true, deadline, whitelisterPk);
        gate.setIsCreditWhitelistedWithSig(whitelister, account, true, deadline, v, r, s);
        assertEq(gate.nonces(whitelister, account), 1);

        (v, r, s) = _signCreditBlacklisted(account, true, deadline, whitelisterPk);
        gate.setIsCreditBlacklistedWithSig(whitelister, account, true, deadline, v, r, s);
        assertEq(gate.nonces(whitelister, account), 2);

        (v, r, s) = _signDebtWhitelisted(account, true, deadline, whitelisterPk);
        gate.setIsDebtWhitelistedWithSig(whitelister, account, true, deadline, v, r, s);
        assertEq(gate.nonces(whitelister, account), 3);

        (v, r, s) = _signDebtBlacklisted(account, true, deadline, whitelisterPk);
        gate.setIsDebtBlacklistedWithSig(whitelister, account, true, deadline, v, r, s);
        assertEq(gate.nonces(whitelister, account), 4);

        assertTrue(gate.isCreditWhitelisted(account));
        assertTrue(gate.isCreditBlacklisted(account));
        assertTrue(gate.isDebtWhitelisted(account));
        assertTrue(gate.isDebtBlacklisted(account));
    }

    function testSetListsWithSigRejectsRevokedWhitelister(address account, bool listed) public {
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v1, bytes32 r1, bytes32 s1) = _signCreditWhitelisted(account, listed, deadline, whitelisterPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _signCreditBlacklisted(account, listed, deadline, whitelisterPk);
        (uint8 v3, bytes32 r3, bytes32 s3) = _signDebtWhitelisted(account, listed, deadline, whitelisterPk);
        (uint8 v4, bytes32 r4, bytes32 s4) = _signDebtBlacklisted(account, listed, deadline, whitelisterPk);

        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, false);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditWhitelistedWithSig(whitelister, account, listed, deadline, v1, r1, s1);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditBlacklistedWithSig(whitelister, account, listed, deadline, v2, r2, s2);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtWhitelistedWithSig(whitelister, account, listed, deadline, v3, r3, s3);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtBlacklistedWithSig(whitelister, account, listed, deadline, v4, r4, s4);
    }

    function testSetListsWithSigDeadlineExpired(address account, bool listed, uint256 deadline, uint256 currentTime)
        public
    {
        deadline = bound(deadline, 0, type(uint256).max - 1);
        currentTime = bound(currentTime, deadline + 1, type(uint256).max);
        vm.warp(currentTime);
        (uint8 v1, bytes32 r1, bytes32 s1) = _signCreditWhitelisted(account, listed, deadline, whitelisterPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _signCreditBlacklisted(account, listed, deadline, whitelisterPk);
        (uint8 v3, bytes32 r3, bytes32 s3) = _signDebtWhitelisted(account, listed, deadline, whitelisterPk);
        (uint8 v4, bytes32 r4, bytes32 s4) = _signDebtBlacklisted(account, listed, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistEnterGate.DeadlineExpired.selector);
        gate.setIsCreditWhitelistedWithSig(whitelister, account, listed, deadline, v1, r1, s1);
        vm.expectRevert(IWhitelistEnterGate.DeadlineExpired.selector);
        gate.setIsCreditBlacklistedWithSig(whitelister, account, listed, deadline, v2, r2, s2);
        vm.expectRevert(IWhitelistEnterGate.DeadlineExpired.selector);
        gate.setIsDebtWhitelistedWithSig(whitelister, account, listed, deadline, v3, r3, s3);
        vm.expectRevert(IWhitelistEnterGate.DeadlineExpired.selector);
        gate.setIsDebtBlacklistedWithSig(whitelister, account, listed, deadline, v4, r4, s4);
    }

    function testSetListsWithSigInvalidSigner(uint256 wrongPk, address account, bool listed, uint256 deadline) public {
        wrongPk = bound(wrongPk, 1, type(uint128).max);
        vm.assume(vm.addr(wrongPk) != whitelister);
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v1, bytes32 r1, bytes32 s1) = _signCreditWhitelisted(account, listed, deadline, wrongPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _signCreditBlacklisted(account, listed, deadline, wrongPk);
        (uint8 v3, bytes32 r3, bytes32 s3) = _signDebtWhitelisted(account, listed, deadline, wrongPk);
        (uint8 v4, bytes32 r4, bytes32 s4) = _signDebtBlacklisted(account, listed, deadline, wrongPk);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditWhitelistedWithSig(vm.addr(wrongPk), account, listed, deadline, v1, r1, s1);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditBlacklistedWithSig(vm.addr(wrongPk), account, listed, deadline, v2, r2, s2);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtWhitelistedWithSig(vm.addr(wrongPk), account, listed, deadline, v3, r3, s3);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtBlacklistedWithSig(vm.addr(wrongPk), account, listed, deadline, v4, r4, s4);
    }

    function testSetListsWithSigEcrecoverReturnsZero(address account, bool listed, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (, bytes32 r1, bytes32 s1) = _signCreditWhitelisted(account, listed, deadline, whitelisterPk);
        (, bytes32 r2, bytes32 s2) = _signCreditBlacklisted(account, listed, deadline, whitelisterPk);
        (, bytes32 r3, bytes32 s3) = _signDebtWhitelisted(account, listed, deadline, whitelisterPk);
        (, bytes32 r4, bytes32 s4) = _signDebtBlacklisted(account, listed, deadline, whitelisterPk);

        // Invalid v (valid values are 27/28) -> ecrecover returns address(0).
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditWhitelistedWithSig(whitelister, account, listed, deadline, 0, r1, s1);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditBlacklistedWithSig(whitelister, account, listed, deadline, 0, r2, s2);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtWhitelistedWithSig(whitelister, account, listed, deadline, 0, r3, s3);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtBlacklistedWithSig(whitelister, account, listed, deadline, 0, r4, s4);
    }

    function testMulticall(address account, bool whitelisted, address account2, bool blacklisted) public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IWhitelistEnterGate.setIsCreditWhitelisted, (account, whitelisted));
        data[1] = abi.encodeCall(IWhitelistEnterGate.setIsDebtBlacklisted, (account2, blacklisted));

        vm.prank(whitelister);
        gate.multicall(data);

        assertEq(gate.isCreditWhitelisted(account), whitelisted);
        assertEq(gate.isDebtBlacklisted(account2), blacklisted);
    }

    function testMulticallBubblesRevert(address caller, address account, bool whitelisted) public {
        vm.assume(caller != whitelister);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(IWhitelistEnterGate.setIsCreditWhitelisted, (account, whitelisted));

        // Called by a non-whitelister: the inner call reverts and the multicall must bubble it up.
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.multicall(data);
    }
}
