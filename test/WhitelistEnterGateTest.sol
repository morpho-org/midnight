// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {WhitelistEnterGate} from "../src/periphery/whitelist-enter-gate/WhitelistEnterGate.sol";
import {
    IWhitelistEnterGate,
    Mode,
    SET_IS_CREDIT_LISTED_TYPEHASH,
    SET_IS_DEBT_LISTED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "../src/periphery/whitelist-enter-gate/interfaces/IWhitelistEnterGate.sol";

bytes constant SET_IS_CREDIT_LISTED_TYPE =
    "SetIsCreditListed(address whitelister,address account,bool newIsCreditListed,uint256 nonce,uint256 deadline)";
bytes constant SET_IS_DEBT_LISTED_TYPE =
    "SetIsDebtListed(address whitelister,address account,bool newIsDebtListed,uint256 nonce,uint256 deadline)";
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

    function _signCredit(address account, bool listed, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_CREDIT_LISTED_TYPEHASH, vm.addr(pk), account, listed, gate.nonces(vm.addr(pk), account), deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", gate.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(pk, digest);
    }

    function _signDebt(address account, bool listed, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_DEBT_LISTED_TYPEHASH, vm.addr(pk), account, listed, gate.nonces(vm.addr(pk), account), deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", gate.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(pk, digest);
    }

    function testSetIsCreditListedTypeHash() public pure {
        assertEq(SET_IS_CREDIT_LISTED_TYPEHASH, keccak256(SET_IS_CREDIT_LISTED_TYPE));
    }

    function testSetIsDebtListedTypeHash() public pure {
        assertEq(SET_IS_DEBT_LISTED_TYPEHASH, keccak256(SET_IS_DEBT_LISTED_TYPE));
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

    function testMultipleWhitelistersCanSetIsListed(address account, address account2) public {
        vm.assume(account != account2);

        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);

        vm.startPrank(whitelister);
        gate.setIsCreditListed(account, true);
        gate.setIsDebtListed(account, true);
        vm.stopPrank();
        vm.startPrank(whitelister2);
        gate.setIsCreditListed(account2, true);
        gate.setIsDebtListed(account2, true);
        vm.stopPrank();

        assertTrue(gate.isCreditListed(account));
        assertTrue(gate.isDebtListed(account));
        assertTrue(gate.isCreditListed(account2));
        assertTrue(gate.isDebtListed(account2));
    }

    function testRevokedWhitelisterCannotSetIsListed(address account) public {
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, false);

        vm.startPrank(whitelister);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        gate.setIsCreditListed(account, true);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        gate.setIsDebtListed(account, true);
        vm.stopPrank();
    }

    function testSetIsCreditListed(address account, bool listed) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsCreditListed(whitelister, account, listed);
        vm.prank(whitelister);
        gate.setIsCreditListed(account, listed);
        assertEq(gate.isCreditListed(account), listed);
        assertFalse(gate.isDebtListed(account));
    }

    function testSetIsDebtListed(address account, bool listed) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsDebtListed(whitelister, account, listed);
        vm.prank(whitelister);
        gate.setIsDebtListed(account, listed);
        assertEq(gate.isDebtListed(account), listed);
        assertFalse(gate.isCreditListed(account));
    }

    function testSetIsListedNotWhitelister(address caller, address account, bool listed) public {
        vm.assume(caller != whitelister);
        vm.startPrank(caller);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        gate.setIsCreditListed(account, listed);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        gate.setIsDebtListed(account, listed);
        vm.stopPrank();
    }

    function testCanIncreaseCreditWhitelist(address account, address other) public {
        vm.assume(account != other);
        vm.prank(whitelister);
        gate.setIsCreditListed(account, true);
        assertTrue(gate.canIncreaseCredit(account));
        assertFalse(gate.canIncreaseCredit(other));
        assertFalse(gate.canIncreaseDebt(account));
    }

    function testCanIncreaseDebtWhitelist(address account, address other) public {
        vm.assume(account != other);
        vm.prank(whitelister);
        gate.setIsDebtListed(account, true);
        assertTrue(gate.canIncreaseDebt(account));
        assertFalse(gate.canIncreaseDebt(other));
        assertFalse(gate.canIncreaseCredit(account));
    }

    function testCanIncreaseCreditBlacklist(address account, address other) public {
        vm.assume(account != other);
        WhitelistEnterGate g = _deploy(Mode.Blacklist, Mode.Whitelist);
        vm.prank(whitelister);
        g.setIsCreditListed(account, true);
        assertFalse(g.canIncreaseCredit(account));
        assertTrue(g.canIncreaseCredit(other));
        assertFalse(g.canIncreaseDebt(other));
    }

    function testCanIncreaseDebtBlacklist(address account, address other) public {
        vm.assume(account != other);
        WhitelistEnterGate g = _deploy(Mode.Whitelist, Mode.Blacklist);
        vm.prank(whitelister);
        g.setIsDebtListed(account, true);
        assertFalse(g.canIncreaseDebt(account));
        assertTrue(g.canIncreaseDebt(other));
        assertFalse(g.canIncreaseCredit(other));
    }

    function testCanIncreaseCreditOpen(address account, bool listed) public {
        WhitelistEnterGate g = _deploy(Mode.Open, Mode.Whitelist);
        vm.prank(whitelister);
        g.setIsCreditListed(account, listed);
        assertTrue(g.canIncreaseCredit(account));
        assertFalse(g.canIncreaseDebt(account));
    }

    function testCanIncreaseDebtOpen(address account, bool listed) public {
        WhitelistEnterGate g = _deploy(Mode.Whitelist, Mode.Open);
        vm.prank(whitelister);
        g.setIsDebtListed(account, listed);
        assertTrue(g.canIncreaseDebt(account));
        assertFalse(g.canIncreaseCredit(account));
    }

    function testSetIsCreditListedWithSig(address account, bool listed, uint256 deadline, address relayer) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _signCredit(account, listed, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsCreditListedWithSig(whitelister, account, listed);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsCreditListedWithSig(whitelister, account, listed, deadline, v, r, s);

        assertEq(gate.isCreditListed(account), listed);
        assertFalse(gate.isDebtListed(account));
        assertEq(gate.nonces(whitelister, account), 1);
    }

    function testSetIsDebtListedWithSig(address account, bool listed, uint256 deadline, address relayer) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _signDebt(account, listed, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsDebtListedWithSig(whitelister, account, listed);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsDebtListedWithSig(whitelister, account, listed, deadline, v, r, s);

        assertEq(gate.isDebtListed(account), listed);
        assertFalse(gate.isCreditListed(account));
        assertEq(gate.nonces(whitelister, account), 1);
    }

    function testSetIsListedWithSigAcceptsAnyWhitelister(address account, bool listed, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);

        (uint8 v, bytes32 r, bytes32 s) = _signCredit(account, listed, deadline, whitelister2Pk);
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsCreditListedWithSig(whitelister2, account, listed);
        gate.setIsCreditListedWithSig(whitelister2, account, listed, deadline, v, r, s);
        assertEq(gate.isCreditListed(account), listed);

        (v, r, s) = _signDebt(account, listed, deadline, whitelister2Pk);
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsDebtListedWithSig(whitelister2, account, listed);
        gate.setIsDebtListedWithSig(whitelister2, account, listed, deadline, v, r, s);
        assertEq(gate.isDebtListed(account), listed);

        assertEq(gate.nonces(whitelister2, account), 2);
    }

    function testNoncesArePerWhitelister(address account, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);

        // Both whitelisters sign for the same account at their own nonce 0.
        (uint8 v1, bytes32 r1, bytes32 s1) = _signCredit(account, true, deadline, whitelisterPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _signCredit(account, true, deadline, whitelister2Pk);

        gate.setIsCreditListedWithSig(whitelister, account, true, deadline, v1, r1, s1);
        gate.setIsCreditListedWithSig(whitelister2, account, true, deadline, v2, r2, s2);

        assertEq(gate.nonces(whitelister, account), 1);
        assertEq(gate.nonces(whitelister2, account), 1);
    }

    function testNoncesAreSharedByBothLists(address account, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);

        (uint8 v, bytes32 r, bytes32 s) = _signCredit(account, true, deadline, whitelisterPk);
        gate.setIsCreditListedWithSig(whitelister, account, true, deadline, v, r, s);
        assertEq(gate.nonces(whitelister, account), 1);

        (v, r, s) = _signDebt(account, true, deadline, whitelisterPk);
        gate.setIsDebtListedWithSig(whitelister, account, true, deadline, v, r, s);
        assertEq(gate.nonces(whitelister, account), 2);

        assertTrue(gate.isCreditListed(account));
        assertTrue(gate.isDebtListed(account));
    }

    function testSetIsListedWithSigRejectsOtherList(address account, bool listed, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);

        (uint8 v, bytes32 r, bytes32 s) = _signCredit(account, listed, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtListedWithSig(whitelister, account, listed, deadline, v, r, s);

        (v, r, s) = _signDebt(account, listed, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditListedWithSig(whitelister, account, listed, deadline, v, r, s);
    }

    function testSetIsListedWithSigRejectsRevokedWhitelister(address account, bool listed) public {
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v1, bytes32 r1, bytes32 s1) = _signCredit(account, listed, deadline, whitelisterPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _signDebt(account, listed, deadline, whitelisterPk);

        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, false);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditListedWithSig(whitelister, account, listed, deadline, v1, r1, s1);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtListedWithSig(whitelister, account, listed, deadline, v2, r2, s2);
    }

    function testSetIsCreditListedWithSigRejectsReplayAndTampering() public {
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _signCredit(alice, true, deadline, whitelisterPk);
        gate.setIsCreditListedWithSig(whitelister, alice, true, deadline, v, r, s);

        // replay
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditListedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong account
        (v, r, s) = _signCredit(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditListedWithSig(whitelister, bob, false, deadline, v, r, s);

        // wrong value
        (v, r, s) = _signCredit(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditListedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong deadline
        (v, r, s) = _signCredit(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditListedWithSig(whitelister, alice, false, deadline + 1, v, r, s);

        // wrong whitelister
        (v, r, s) = _signCredit(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditListedWithSig(whitelister2, alice, false, deadline, v, r, s);

        // wrong domain separator
        (v, r, s) = _signCredit(bob, true, deadline, whitelisterPk);
        WhitelistEnterGate otherGate = _deploy(Mode.Whitelist, Mode.Whitelist);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        otherGate.setIsCreditListedWithSig(whitelister, bob, true, deadline, v, r, s);
    }

    function testSetIsDebtListedWithSigRejectsReplayAndTampering() public {
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _signDebt(alice, true, deadline, whitelisterPk);
        gate.setIsDebtListedWithSig(whitelister, alice, true, deadline, v, r, s);

        // replay
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtListedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong account
        (v, r, s) = _signDebt(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtListedWithSig(whitelister, bob, false, deadline, v, r, s);

        // wrong value
        (v, r, s) = _signDebt(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtListedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong deadline
        (v, r, s) = _signDebt(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtListedWithSig(whitelister, alice, false, deadline + 1, v, r, s);

        // wrong whitelister
        (v, r, s) = _signDebt(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtListedWithSig(whitelister2, alice, false, deadline, v, r, s);

        // wrong domain separator
        (v, r, s) = _signDebt(bob, true, deadline, whitelisterPk);
        WhitelistEnterGate otherGate = _deploy(Mode.Whitelist, Mode.Whitelist);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        otherGate.setIsDebtListedWithSig(whitelister, bob, true, deadline, v, r, s);
    }

    function testSetIsListedWithSigDeadlineExpired(address account, bool listed, uint256 deadline, uint256 currentTime)
        public
    {
        deadline = bound(deadline, 0, type(uint256).max - 1);
        currentTime = bound(currentTime, deadline + 1, type(uint256).max);
        vm.warp(currentTime);
        (uint8 v1, bytes32 r1, bytes32 s1) = _signCredit(account, listed, deadline, whitelisterPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _signDebt(account, listed, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistEnterGate.DeadlineExpired.selector);
        gate.setIsCreditListedWithSig(whitelister, account, listed, deadline, v1, r1, s1);
        vm.expectRevert(IWhitelistEnterGate.DeadlineExpired.selector);
        gate.setIsDebtListedWithSig(whitelister, account, listed, deadline, v2, r2, s2);
    }

    function testSetIsListedWithSigInvalidSigner(uint256 wrongPk, address account, bool listed, uint256 deadline)
        public
    {
        wrongPk = bound(wrongPk, 1, type(uint128).max);
        vm.assume(vm.addr(wrongPk) != whitelister);
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v1, bytes32 r1, bytes32 s1) = _signCredit(account, listed, deadline, wrongPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _signDebt(account, listed, deadline, wrongPk);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditListedWithSig(vm.addr(wrongPk), account, listed, deadline, v1, r1, s1);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtListedWithSig(vm.addr(wrongPk), account, listed, deadline, v2, r2, s2);
    }

    function testSetIsListedWithSigEcrecoverReturnsZero(address account, bool listed, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (, bytes32 r1, bytes32 s1) = _signCredit(account, listed, deadline, whitelisterPk);
        (, bytes32 r2, bytes32 s2) = _signDebt(account, listed, deadline, whitelisterPk);

        // Invalid v (valid values are 27/28) -> ecrecover returns address(0).
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsCreditListedWithSig(whitelister, account, listed, deadline, 0, r1, s1);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsDebtListedWithSig(whitelister, account, listed, deadline, 0, r2, s2);
    }

    function testMulticall(address account, bool listed, address account2, bool listed2) public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IWhitelistEnterGate.setIsCreditListed, (account, listed));
        data[1] = abi.encodeCall(IWhitelistEnterGate.setIsDebtListed, (account2, listed2));

        vm.prank(whitelister);
        gate.multicall(data);

        assertEq(gate.isCreditListed(account), listed);
        assertEq(gate.isDebtListed(account2), listed2);
    }

    function testMulticallBubblesRevert(address caller, address account, bool listed) public {
        vm.assume(caller != whitelister);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(IWhitelistEnterGate.setIsCreditListed, (account, listed));

        // Called by a non-whitelister: the inner call reverts and the multicall must bubble it up.
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.multicall(data);
    }
}
