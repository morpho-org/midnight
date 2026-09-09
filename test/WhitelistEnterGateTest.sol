// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {WhitelistEnterGate} from "../src/periphery/whitelist-enter-gate/WhitelistEnterGate.sol";
import {
    IWhitelistEnterGate,
    SET_IS_WHITELISTED_TYPEHASH,
    SET_IS_GLOBALLY_WHITELISTED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "../src/periphery/whitelist-enter-gate/interfaces/IWhitelistEnterGate.sol";

bytes constant SET_IS_WHITELISTED_TYPE =
    "SetIsWhitelisted(address whitelister,bool creditSide,address account,bool newIsWhitelisted,uint256 nonce,uint256 deadline)";
bytes constant SET_IS_GLOBALLY_WHITELISTED_TYPE =
    "SetIsGloballyWhitelisted(address whitelister,address account,bool newIsWhitelisted,uint256 nonce,uint256 deadline)";
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
        gate = _deploy(false, false);
    }

    function _deploy(bool creditOpen, bool debtOpen) internal returns (WhitelistEnterGate g) {
        g = new WhitelistEnterGate(roleSetter, creditOpen, debtOpen);
        vm.startPrank(roleSetter);
        g.setIsGlobalWhitelister(whitelister, true);
        g.setIsWhitelister(true, whitelister, true);
        g.setIsWhitelister(false, whitelister, true);
        vm.stopPrank();
    }

    function _sign(bool creditSide, address account, bool listed, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_WHITELISTED_TYPEHASH,
                vm.addr(pk),
                creditSide,
                account,
                listed,
                gate.nonces(vm.addr(pk), account),
                deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", gate.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(pk, digest);
    }

    function _signGlobal(address account, bool listed, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_GLOBALLY_WHITELISTED_TYPEHASH,
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

    function testSetIsWhitelistedTypeHash() public pure {
        assertEq(SET_IS_WHITELISTED_TYPEHASH, keccak256(SET_IS_WHITELISTED_TYPE));
    }

    function testSetIsGloballyWhitelistedTypeHash() public pure {
        assertEq(SET_IS_GLOBALLY_WHITELISTED_TYPEHASH, keccak256(SET_IS_GLOBALLY_WHITELISTED_TYPE));
    }

    function testEip712DomainTypeHash() public pure {
        assertEq(EIP712_DOMAIN_TYPEHASH, keccak256(EIP712_DOMAIN_TYPE));
    }

    function testDomainSeparator() public view {
        bytes32 expected = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(gate)));
        assertEq(gate.DOMAIN_SEPARATOR(), expected);
    }

    function testConstructor(address _roleSetter, bool creditOpen, bool debtOpen) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.Constructor(_roleSetter, creditOpen, debtOpen);
        WhitelistEnterGate g = new WhitelistEnterGate(_roleSetter, creditOpen, debtOpen);
        assertEq(g.roleSetter(), _roleSetter);
        assertEq(g.CREDIT_OPEN(), creditOpen);
        assertEq(g.DEBT_OPEN(), debtOpen);
        assertFalse(g.isGlobalWhitelister(_roleSetter));
        assertFalse(g.isWhitelister(true, _roleSetter));
        assertFalse(g.isWhitelister(false, _roleSetter));
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

    function testSetIsGlobalWhitelister(address account, bool newIsWhitelister) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsGlobalWhitelister(account, newIsWhitelister);
        vm.prank(roleSetter);
        gate.setIsGlobalWhitelister(account, newIsWhitelister);
        assertEq(gate.isGlobalWhitelister(account), newIsWhitelister);
    }

    function testSetIsWhitelister(bool creditSide, address account, bool newIsWhitelister) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsWhitelister(creditSide, account, newIsWhitelister);
        vm.prank(roleSetter);
        gate.setIsWhitelister(creditSide, account, newIsWhitelister);
        assertEq(gate.isWhitelister(creditSide, account), newIsWhitelister);
        assertFalse(gate.isWhitelister(!creditSide, account));
    }

    function testSetIsGlobalWhitelisterNotRoleSetter(address caller, address account, bool newIsWhitelister) public {
        vm.assume(caller != roleSetter);
        vm.expectRevert(IWhitelistEnterGate.NotRoleSetter.selector);
        vm.prank(caller);
        gate.setIsGlobalWhitelister(account, newIsWhitelister);
    }

    function testSetIsWhitelisterNotRoleSetter(address caller, bool creditSide, address account, bool newIsWhitelister)
        public
    {
        vm.assume(caller != roleSetter);
        vm.expectRevert(IWhitelistEnterGate.NotRoleSetter.selector);
        vm.prank(caller);
        gate.setIsWhitelister(creditSide, account, newIsWhitelister);
    }

    function testWhitelisterCannotSetWhitelisterRoles(bool creditSide, address account, bool newIsWhitelister) public {
        vm.startPrank(whitelister);
        vm.expectRevert(IWhitelistEnterGate.NotRoleSetter.selector);
        gate.setIsGlobalWhitelister(account, newIsWhitelister);
        vm.expectRevert(IWhitelistEnterGate.NotRoleSetter.selector);
        gate.setIsWhitelister(creditSide, account, newIsWhitelister);
        vm.stopPrank();
    }

    function testSetIsWhitelisted(bool creditSide, address account, bool listed) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsWhitelisted(whitelister, creditSide, account, listed);
        vm.prank(whitelister);
        gate.setIsWhitelisted(creditSide, account, listed);
        assertEq(gate.isWhitelisted(creditSide, account), listed);
        assertFalse(gate.isWhitelisted(!creditSide, account));
    }

    function testSetIsWhitelistedNotWhitelister(address caller, bool creditSide, address account, bool listed) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setIsWhitelisted(creditSide, account, listed);
    }

    function testRevokedWhitelisterCannotSetIsWhitelisted(bool creditSide, address account) public {
        vm.prank(roleSetter);
        gate.setIsWhitelister(creditSide, whitelister, false);

        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(whitelister);
        gate.setIsWhitelisted(creditSide, account, true);
    }

    function testMultipleWhitelistersCanSetIsWhitelisted(bool creditSide, address account, address account2) public {
        vm.assume(account != account2);

        vm.prank(roleSetter);
        gate.setIsWhitelister(creditSide, whitelister2, true);

        vm.prank(whitelister);
        gate.setIsWhitelisted(creditSide, account, true);
        vm.prank(whitelister2);
        gate.setIsWhitelisted(creditSide, account2, true);

        assertTrue(gate.isWhitelisted(creditSide, account));
        assertTrue(gate.isWhitelisted(creditSide, account2));
    }

    function testSetIsGloballyWhitelisted(address account, bool listed) public {
        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsGloballyWhitelisted(whitelister, account, listed);
        vm.prank(whitelister);
        gate.setIsGloballyWhitelisted(account, listed);
        assertEq(gate.isGloballyWhitelisted(account), listed);
    }

    function testSetIsGloballyWhitelistedNotGlobalWhitelister(address caller, address account, bool listed) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setIsGloballyWhitelisted(account, listed);
    }

    function testRevokedGlobalWhitelisterCannotSetIsGloballyWhitelisted(address account) public {
        vm.prank(roleSetter);
        gate.setIsGlobalWhitelister(whitelister, false);

        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(whitelister);
        gate.setIsGloballyWhitelisted(account, true);
    }

    function testWhitelistersAreScopedToTheirList(bool creditSide, address account) public {
        vm.startPrank(roleSetter);
        gate.setIsGlobalWhitelister(whitelister2, true);
        gate.setIsWhitelister(creditSide, alice, true);
        vm.stopPrank();

        vm.prank(whitelister2);
        gate.setIsGloballyWhitelisted(account, true);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(whitelister2);
        gate.setIsWhitelisted(creditSide, account, true);

        vm.prank(alice);
        gate.setIsWhitelisted(creditSide, account, true);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(alice);
        gate.setIsWhitelisted(!creditSide, account, true);
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(alice);
        gate.setIsGloballyWhitelisted(account, true);
    }

    function testCanIncreaseCreditRequiresGlobalAndCreditWhitelists(address account, address other) public {
        vm.assume(account != other);
        vm.startPrank(whitelister);
        gate.setIsWhitelisted(true, account, true);
        assertFalse(gate.canIncreaseCredit(account));
        gate.setIsGloballyWhitelisted(account, true);
        vm.stopPrank();

        assertTrue(gate.canIncreaseCredit(account));
        assertFalse(gate.canIncreaseCredit(other));
        assertFalse(gate.canIncreaseDebt(account));
    }

    function testCanIncreaseDebtRequiresGlobalAndDebtWhitelists(address account, address other) public {
        vm.assume(account != other);
        vm.startPrank(whitelister);
        gate.setIsWhitelisted(false, account, true);
        assertFalse(gate.canIncreaseDebt(account));
        gate.setIsGloballyWhitelisted(account, true);
        vm.stopPrank();

        assertTrue(gate.canIncreaseDebt(account));
        assertFalse(gate.canIncreaseDebt(other));
        assertFalse(gate.canIncreaseCredit(account));
    }

    function testGlobalWhitelistAppliesToBothSides(address account) public {
        vm.startPrank(whitelister);
        gate.setIsWhitelisted(true, account, true);
        gate.setIsWhitelisted(false, account, true);
        vm.stopPrank();

        assertFalse(gate.canIncreaseCredit(account));
        assertFalse(gate.canIncreaseDebt(account));

        vm.prank(whitelister);
        gate.setIsGloballyWhitelisted(account, true);
        assertTrue(gate.canIncreaseCredit(account));
        assertTrue(gate.canIncreaseDebt(account));
    }

    function testOpenCreditSideLetsAnyoneIn(address account, address other) public {
        vm.assume(account != other);
        gate = _deploy(true, false);
        vm.startPrank(whitelister);
        gate.setIsGloballyWhitelisted(account, true);
        gate.setIsWhitelisted(false, account, true);
        vm.stopPrank();

        assertTrue(gate.canIncreaseCredit(account));
        assertTrue(gate.canIncreaseCredit(other));
        assertTrue(gate.canIncreaseDebt(account));
        assertFalse(gate.canIncreaseDebt(other));
    }

    function testOpenDebtSideLetsAnyoneIn(address account, address other) public {
        vm.assume(account != other);
        gate = _deploy(false, true);
        vm.startPrank(whitelister);
        gate.setIsGloballyWhitelisted(account, true);
        gate.setIsWhitelisted(true, account, true);
        vm.stopPrank();

        assertTrue(gate.canIncreaseDebt(account));
        assertTrue(gate.canIncreaseDebt(other));
        assertTrue(gate.canIncreaseCredit(account));
        assertFalse(gate.canIncreaseCredit(other));
    }

    function testOpenSideIgnoresAllWhitelists(bool creditSide, address account) public {
        gate = _deploy(creditSide, !creditSide);
        assertTrue(creditSide ? gate.canIncreaseCredit(account) : gate.canIncreaseDebt(account));
    }

    function testSetIsGloballyWhitelistedWithSig(address account, bool listed, uint256 deadline, address relayer)
        public
    {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _signGlobal(account, listed, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsGloballyWhitelistedWithSig(whitelister, account, listed);
        vm.prank(relayer);
        gate.setIsGloballyWhitelistedWithSig(whitelister, account, listed, deadline, v, r, s);

        assertEq(gate.isGloballyWhitelisted(account), listed);
        assertEq(gate.nonces(whitelister, account), 1);
    }

    function testSetIsGloballyWhitelistedWithSigRejectsSideWhitelister(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(roleSetter);
        gate.setIsWhitelister(creditSide, whitelister2, true);
        (uint8 v, bytes32 r, bytes32 s) = _signGlobal(account, listed, deadline, whitelister2Pk);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsGloballyWhitelistedWithSig(whitelister2, account, listed, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSig(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline,
        address relayer
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsWhitelistedWithSig(whitelister, creditSide, account, listed);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsWhitelistedWithSig(whitelister, creditSide, account, listed, deadline, v, r, s);

        assertEq(gate.isWhitelisted(creditSide, account), listed);
        assertFalse(gate.isWhitelisted(!creditSide, account));
        assertEq(gate.nonces(whitelister, account), 1);
    }

    function testSetIsWhitelistedWithSigRejectsOtherSide(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, !creditSide, account, listed, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigAcceptsAnyWhitelister(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline,
        address relayer
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(roleSetter);
        gate.setIsWhitelister(creditSide, whitelister2, true);
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, deadline, whitelister2Pk);

        vm.expectEmit();
        emit IWhitelistEnterGate.SetIsWhitelistedWithSig(whitelister2, creditSide, account, listed);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsWhitelistedWithSig(whitelister2, creditSide, account, listed, deadline, v, r, s);

        assertEq(gate.isWhitelisted(creditSide, account), listed);
        assertEq(gate.nonces(whitelister2, account), 1);
    }

    function testNoncesArePerWhitelister(bool creditSide, address account, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(roleSetter);
        gate.setIsWhitelister(creditSide, whitelister2, true);

        // Both whitelisters sign for the same account at their own nonce 0.
        (uint8 v1, bytes32 r1, bytes32 s1) = _sign(creditSide, account, true, deadline, whitelisterPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _sign(creditSide, account, true, deadline, whitelister2Pk);

        gate.setIsWhitelistedWithSig(whitelister, creditSide, account, true, deadline, v1, r1, s1);
        gate.setIsWhitelistedWithSig(whitelister2, creditSide, account, true, deadline, v2, r2, s2);

        assertEq(gate.nonces(whitelister, account), 1);
        assertEq(gate.nonces(whitelister2, account), 1);
    }

    function testNoncesAreSharedByAllLists(address account, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);

        (uint8 v, bytes32 r, bytes32 s) = _signGlobal(account, true, deadline, whitelisterPk);
        gate.setIsGloballyWhitelistedWithSig(whitelister, account, true, deadline, v, r, s);
        assertEq(gate.nonces(whitelister, account), 1);

        (v, r, s) = _sign(true, account, true, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(whitelister, true, account, true, deadline, v, r, s);
        assertEq(gate.nonces(whitelister, account), 2);

        (v, r, s) = _sign(false, account, true, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(whitelister, false, account, true, deadline, v, r, s);
        assertEq(gate.nonces(whitelister, account), 3);
    }

    function testSetIsWhitelistedWithSigRejectsRevokedWhitelister(bool creditSide, address account, bool listed)
        public
    {
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, deadline, whitelisterPk);

        vm.prank(roleSetter);
        gate.setIsWhitelister(creditSide, whitelister, false);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, creditSide, account, listed, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigRejectsReplayAndTampering() public {
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _sign(true, alice, true, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(whitelister, true, alice, true, deadline, v, r, s);

        // replay
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, true, alice, true, deadline, v, r, s);

        // wrong side
        (v, r, s) = _sign(true, alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, false, alice, false, deadline, v, r, s);

        // wrong account
        (v, r, s) = _sign(true, alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, true, bob, false, deadline, v, r, s);

        // wrong value
        (v, r, s) = _sign(true, alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, true, alice, true, deadline, v, r, s);

        // wrong deadline
        (v, r, s) = _sign(true, alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, true, alice, false, deadline + 1, v, r, s);

        // wrong whitelister
        (v, r, s) = _sign(true, alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister2, true, alice, false, deadline, v, r, s);

        // wrong domain separator
        (v, r, s) = _sign(true, bob, true, deadline, whitelisterPk);
        WhitelistEnterGate otherGate = _deploy(false, false);
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        otherGate.setIsWhitelistedWithSig(whitelister, true, bob, true, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigDeadlineExpired(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline,
        uint256 currentTime
    ) public {
        deadline = bound(deadline, 0, type(uint256).max - 1);
        currentTime = bound(currentTime, deadline + 1, type(uint256).max);
        vm.warp(currentTime);
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistEnterGate.DeadlineExpired.selector);
        gate.setIsWhitelistedWithSig(whitelister, creditSide, account, listed, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigInvalidSigner(
        uint256 wrongPk,
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline
    ) public {
        wrongPk = bound(wrongPk, 1, type(uint128).max);
        vm.assume(vm.addr(wrongPk) != whitelister);
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, deadline, wrongPk);

        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(vm.addr(wrongPk), creditSide, account, listed, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigEcrecoverReturnsZero(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, deadline, whitelisterPk);

        // Invalid v (valid values are 27/28) -> ecrecover returns address(0).
        vm.expectRevert(IWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, creditSide, account, listed, deadline, 0, r, s);
    }

    function testMulticall(address account, bool creditListed, address account2, bool debtListed) public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IWhitelistEnterGate.setIsWhitelisted, (true, account, creditListed));
        data[1] = abi.encodeCall(IWhitelistEnterGate.setIsWhitelisted, (false, account2, debtListed));

        vm.prank(whitelister);
        gate.multicall(data);

        assertEq(gate.isWhitelisted(true, account), creditListed);
        assertEq(gate.isWhitelisted(false, account2), debtListed);
    }

    function testMulticallBubblesRevert(address caller, bool creditSide, address account, bool listed) public {
        vm.assume(caller != whitelister);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(IWhitelistEnterGate.setIsWhitelisted, (creditSide, account, listed));

        // Called by a non-whitelister: the inner call reverts and the multicall must bubble it up.
        vm.expectRevert(IWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.multicall(data);
    }
}
