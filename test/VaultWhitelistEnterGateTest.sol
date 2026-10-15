// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {IMidnight, Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {VaultWhitelistEnterGate} from "../src/periphery/vault-whitelist-enter-gate/VaultWhitelistEnterGate.sol";
import {
    IVaultWhitelistEnterGate,
    IMidnightAdapter,
    IMidnightAdapterFactory,
    IVault,
    SET_IS_WHITELISTED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "../src/periphery/vault-whitelist-enter-gate/interfaces/IVaultWhitelistEnterGate.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

bytes constant SET_IS_WHITELISTED_TYPE =
    "SetIsWhitelisted(bool creditSide,address account,bool newIsWhitelisted,uint256 nonce,uint256 deadline)";
bytes constant EIP712_DOMAIN_TYPE = "EIP712Domain(uint256 chainId,address verifyingContract)";

contract VaultWhitelistEnterGateTest is Test {
    VaultWhitelistEnterGate internal gate;
    uint256 internal whitelisterPk;
    uint256 internal whitelister2Pk;
    address internal creditRoleSetter = makeAddr("creditRoleSetter");
    address internal debtRoleSetter = makeAddr("debtRoleSetter");
    address internal whitelister;
    address internal whitelister2;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal adapterFactory = makeAddr("adapterFactory");
    address internal adapter = makeAddr("adapter");
    address internal vault = makeAddr("vault");
    address internal midnight = makeAddr("midnight");
    bytes32 internal marketId = keccak256("marketId");

    function setUp() public {
        whitelisterPk = 0xA11CE;
        whitelister2Pk = 0xB0B;
        whitelister = vm.addr(whitelisterPk);
        whitelister2 = vm.addr(whitelister2Pk);
        gate = _deploy(false, false);
    }

    /// @dev Deploys a gate where whitelister is a whitelister on both sides.
    function _deploy(bool creditOpen, bool debtOpen) internal returns (VaultWhitelistEnterGate g) {
        g = new VaultWhitelistEnterGate(creditRoleSetter, debtRoleSetter, creditOpen, debtOpen);
        vm.prank(creditRoleSetter);
        g.setIsWhitelister(true, whitelister, true);
        vm.prank(debtRoleSetter);
        g.setIsWhitelister(false, whitelister, true);
    }

    function _roleSetter(bool creditSide) internal view returns (address) {
        return creditSide ? creditRoleSetter : debtRoleSetter;
    }

    function _sign(bool creditSide, address account, bool listed, uint256 nonce, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct =
            keccak256(abi.encode(SET_IS_WHITELISTED_TYPEHASH, creditSide, account, listed, nonce, deadline));
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

    function testConstructor(address _creditRoleSetter, address _debtRoleSetter, bool creditOpen, bool debtOpen)
        public
    {
        vm.expectEmit();
        emit IVaultWhitelistEnterGate.Constructor(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen);
        VaultWhitelistEnterGate g =
            new VaultWhitelistEnterGate(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen);
        assertEq(g.roleSetter(true), _creditRoleSetter);
        assertEq(g.roleSetter(false), _debtRoleSetter);
        assertEq(g.CREDIT_OPEN(), creditOpen);
        assertEq(g.DEBT_OPEN(), debtOpen);
        assertFalse(g.isWhitelister(true, _creditRoleSetter));
        assertFalse(g.isWhitelister(false, _debtRoleSetter));
    }

    function testSetRoleSetter(bool creditSide, address newRoleSetter) public {
        vm.expectEmit();
        emit IVaultWhitelistEnterGate.SetRoleSetter(creditSide, newRoleSetter);
        vm.prank(_roleSetter(creditSide));
        gate.setRoleSetter(creditSide, newRoleSetter);
        assertEq(gate.roleSetter(creditSide), newRoleSetter);
        // The other side is unaffected.
        assertEq(gate.roleSetter(!creditSide), _roleSetter(!creditSide));
    }

    function testSetRoleSetterNotRoleSetter(address caller, bool creditSide, address newRoleSetter) public {
        vm.assume(caller != _roleSetter(creditSide));
        vm.expectRevert(IVaultWhitelistEnterGate.NotRoleSetter.selector);
        vm.prank(caller);
        gate.setRoleSetter(creditSide, newRoleSetter);
    }

    function testRoleSetterCannotSetOtherSideRoleSetter(bool creditSide, address newRoleSetter) public {
        vm.expectRevert(IVaultWhitelistEnterGate.NotRoleSetter.selector);
        vm.prank(_roleSetter(!creditSide));
        gate.setRoleSetter(creditSide, newRoleSetter);
    }

    function testSetIsWhitelister(bool creditSide, address account, bool isWhitelister_) public {
        vm.assume(account != whitelister);
        vm.expectEmit();
        emit IVaultWhitelistEnterGate.SetIsWhitelister(creditSide, account, isWhitelister_);
        vm.prank(_roleSetter(creditSide));
        gate.setIsWhitelister(creditSide, account, isWhitelister_);
        assertEq(gate.isWhitelister(creditSide, account), isWhitelister_);
        // The other side is unaffected.
        assertFalse(gate.isWhitelister(!creditSide, account));
    }

    function testSetIsWhitelisterNotRoleSetter(address caller, bool creditSide, address account, bool isWhitelister_)
        public
    {
        vm.assume(caller != _roleSetter(creditSide));
        vm.expectRevert(IVaultWhitelistEnterGate.NotRoleSetter.selector);
        vm.prank(caller);
        gate.setIsWhitelister(creditSide, account, isWhitelister_);
    }

    function testRoleSetterCannotSetOtherSideWhitelister(bool creditSide, address account, bool isWhitelister_) public {
        vm.expectRevert(IVaultWhitelistEnterGate.NotRoleSetter.selector);
        vm.prank(_roleSetter(!creditSide));
        gate.setIsWhitelister(creditSide, account, isWhitelister_);
    }

    function testWhitelisterCannotSetIsWhitelister(bool creditSide, address account, bool isWhitelister_) public {
        vm.expectRevert(IVaultWhitelistEnterGate.NotRoleSetter.selector);
        vm.prank(whitelister);
        gate.setIsWhitelister(creditSide, account, isWhitelister_);
    }

    function testSetIsWhitelisted(bool creditSide, address account, bool listed) public {
        vm.expectEmit();
        emit IVaultWhitelistEnterGate.SetIsWhitelisted(whitelister, creditSide, account, listed);
        vm.prank(whitelister);
        gate.setIsWhitelisted(creditSide, account, listed);
        assertEq(gate.isWhitelisted(creditSide, account), listed);
        assertFalse(gate.isWhitelisted(!creditSide, account));
    }

    function testSetIsWhitelistedNotWhitelister(address caller, bool creditSide, address account, bool listed) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IVaultWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setIsWhitelisted(creditSide, account, listed);
    }

    function testWhitelisterCannotSetOtherSideList(bool creditSide, address account, bool listed) public {
        // whitelister2 is a whitelister on creditSide only.
        vm.prank(_roleSetter(creditSide));
        gate.setIsWhitelister(creditSide, whitelister2, true);

        vm.expectRevert(IVaultWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(whitelister2);
        gate.setIsWhitelisted(!creditSide, account, listed);

        vm.prank(whitelister2);
        gate.setIsWhitelisted(creditSide, account, listed);
        assertEq(gate.isWhitelisted(creditSide, account), listed);
    }

    function testRevokedWhitelisterCannotSetIsWhitelisted(bool creditSide, address account) public {
        vm.prank(_roleSetter(creditSide));
        gate.setIsWhitelister(creditSide, whitelister, false);

        vm.expectRevert(IVaultWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(whitelister);
        gate.setIsWhitelisted(creditSide, account, true);

        // Still a whitelister on the other side.
        vm.prank(whitelister);
        gate.setIsWhitelisted(!creditSide, account, true);
        assertTrue(gate.isWhitelisted(!creditSide, account));
    }

    function testMultipleWhitelistersCanSetIsWhitelisted(bool creditSide, address account, address account2) public {
        vm.assume(account != account2);

        vm.prank(_roleSetter(creditSide));
        gate.setIsWhitelister(creditSide, whitelister2, true);

        vm.prank(whitelister);
        gate.setIsWhitelisted(creditSide, account, true);
        vm.prank(whitelister2);
        gate.setIsWhitelisted(creditSide, account2, true);

        assertTrue(gate.isWhitelisted(creditSide, account));
        assertTrue(gate.isWhitelisted(creditSide, account2));
    }

    function testCanIncreaseCredit(address account, address other) public {
        vm.assume(account != other);
        vm.prank(whitelister);
        gate.setIsWhitelisted(true, account, true);
        assertTrue(gate.canIncreaseCredit(account));
        assertFalse(gate.canIncreaseCredit(other));
    }

    function testCanIncreaseCreditIgnoresDebtList(address account, bool listed) public {
        vm.prank(whitelister);
        gate.setIsWhitelisted(false, account, listed);
        assertFalse(gate.canIncreaseCredit(account));
    }

    function testCanIncreaseDebt(address account, address other) public {
        vm.assume(account != other);
        vm.prank(whitelister);
        gate.setIsWhitelisted(false, account, true);
        assertTrue(gate.canIncreaseDebt(account));
        assertFalse(gate.canIncreaseDebt(other));
    }

    function testCanIncreaseDebtIgnoresCreditList(address account, bool listed) public {
        vm.prank(whitelister);
        gate.setIsWhitelisted(true, account, listed);
        assertFalse(gate.canIncreaseDebt(account));
    }

    function testSidesAreIndependent(address account, bool creditListed, bool debtListed) public {
        vm.startPrank(whitelister);
        gate.setIsWhitelisted(true, account, creditListed);
        gate.setIsWhitelisted(false, account, debtListed);
        vm.stopPrank();
        assertEq(gate.isWhitelisted(true, account), creditListed);
        assertEq(gate.isWhitelisted(false, account), debtListed);
        assertEq(gate.canIncreaseCredit(account), creditListed);
        assertEq(gate.canIncreaseDebt(account), debtListed);
    }

    function testOpenCreditSideLetsAnyoneIn(address account, address other) public {
        vm.assume(account != other);
        gate = _deploy(true, false);
        vm.prank(whitelister);
        gate.setIsWhitelisted(false, account, true);

        assertTrue(gate.canIncreaseCredit(account));
        assertTrue(gate.canIncreaseCredit(other));
        // The debt side still honours its whitelist.
        assertTrue(gate.canIncreaseDebt(account));
        assertFalse(gate.canIncreaseDebt(other));
    }

    function testOpenDebtSideLetsAnyoneIn(address account, address other) public {
        vm.assume(account != other);
        gate = _deploy(false, true);
        vm.prank(whitelister);
        gate.setIsWhitelisted(true, account, true);

        assertTrue(gate.canIncreaseDebt(account));
        assertTrue(gate.canIncreaseDebt(other));
        // The credit side still honours its whitelist.
        assertTrue(gate.canIncreaseCredit(account));
        assertFalse(gate.canIncreaseCredit(other));
    }

    function testOpenSideIgnoresWhitelist(bool creditSide, address account, bool whitelisted) public {
        gate = _deploy(creditSide, !creditSide);
        vm.prank(whitelister);
        gate.setIsWhitelisted(creditSide, account, whitelisted);
        assertTrue(creditSide ? gate.canIncreaseCredit(account) : gate.canIncreaseDebt(account));
    }

    function testSetIsWhitelistedWithSig(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline,
        address relayer
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, 0, deadline, whitelisterPk);

        vm.expectEmit();
        emit IVaultWhitelistEnterGate.SetIsWhitelistedWithSig(relayer, whitelister, creditSide, account, listed, 0, 0);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsWhitelistedWithSig(creditSide, account, listed, 0, deadline, v, r, s);

        assertEq(gate.isWhitelisted(creditSide, account), listed);
        assertFalse(gate.isWhitelisted(!creditSide, account));
        assertEq(gate.nonces(creditSide, whitelister, account), 1);
    }

    function testSetIsWhitelistedWithSigRejectsOtherSide(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, 0, deadline, whitelisterPk);

        vm.expectRevert(IVaultWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(!creditSide, account, listed, 0, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigRejectsOtherSideWhitelister(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        // whitelister2 is a whitelister on the other side only.
        vm.prank(_roleSetter(!creditSide));
        gate.setIsWhitelister(!creditSide, whitelister2, true);
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, 0, deadline, whitelister2Pk);

        vm.expectRevert(IVaultWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(creditSide, account, listed, 0, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigAcceptsAnyWhitelister(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline,
        address relayer
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(_roleSetter(creditSide));
        gate.setIsWhitelister(creditSide, whitelister2, true);
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, 0, deadline, whitelister2Pk);

        vm.expectEmit();
        emit IVaultWhitelistEnterGate.SetIsWhitelistedWithSig(relayer, whitelister2, creditSide, account, listed, 0, 0);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsWhitelistedWithSig(creditSide, account, listed, 0, deadline, v, r, s);

        assertEq(gate.isWhitelisted(creditSide, account), listed);
        assertEq(gate.nonces(creditSide, whitelister2, account), 1);
    }

    function testNoncesArePerWhitelister(bool creditSide, address account, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(_roleSetter(creditSide));
        gate.setIsWhitelister(creditSide, whitelister2, true);

        // Both whitelisters sign for the same account at their own nonce 0.
        (uint8 v1, bytes32 r1, bytes32 s1) = _sign(creditSide, account, true, 0, deadline, whitelisterPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _sign(creditSide, account, true, 0, deadline, whitelister2Pk);

        gate.setIsWhitelistedWithSig(creditSide, account, true, 0, deadline, v1, r1, s1);
        gate.setIsWhitelistedWithSig(creditSide, account, true, 0, deadline, v2, r2, s2);

        assertEq(gate.nonces(creditSide, whitelister, account), 1);
        assertEq(gate.nonces(creditSide, whitelister2, account), 1);
    }

    function testNoncesArePerSide(bool creditSide, address account, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);

        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, true, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(creditSide, account, true, 0, deadline, v, r, s);
        assertEq(gate.nonces(creditSide, whitelister, account), 1);
        assertEq(gate.nonces(!creditSide, whitelister, account), 0);

        // The other side signature still uses nonce 0.
        (v, r, s) = _sign(!creditSide, account, true, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(!creditSide, account, true, 0, deadline, v, r, s);
        assertEq(gate.nonces(creditSide, whitelister, account), 1);
        assertEq(gate.nonces(!creditSide, whitelister, account), 1);
    }

    function testSetIsWhitelistedWithSigRejectsRevokedWhitelister(bool creditSide, address account, bool listed)
        public
    {
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, 0, deadline, whitelisterPk);

        vm.prank(_roleSetter(creditSide));
        gate.setIsWhitelister(creditSide, whitelister, false);

        vm.expectRevert(IVaultWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(creditSide, account, listed, 0, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigRejectsReplayAndTampering() public {
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _sign(true, alice, true, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(true, alice, true, 0, deadline, v, r, s);
        assertEq(gate.nonces(true, whitelister, alice), 1);

        // replay is a no-op
        gate.setIsWhitelistedWithSig(true, alice, true, 0, deadline, v, r, s);
        assertEq(gate.nonces(true, whitelister, alice), 1);

        // wrong side
        (v, r, s) = _sign(true, alice, false, 0, deadline, whitelisterPk);
        vm.expectRevert(IVaultWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(false, alice, false, 0, deadline, v, r, s);

        // wrong account
        (v, r, s) = _sign(true, alice, false, 0, deadline, whitelisterPk);
        vm.expectRevert(IVaultWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(true, bob, false, 0, deadline, v, r, s);

        // wrong value
        (v, r, s) = _sign(true, alice, false, 1, deadline, whitelisterPk);
        vm.expectRevert(IVaultWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(true, alice, true, 1, deadline, v, r, s);

        // wrong deadline
        (v, r, s) = _sign(true, alice, false, 1, deadline, whitelisterPk);
        vm.expectRevert(IVaultWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(true, alice, false, 1, deadline + 1, v, r, s);

        // wrong nonce
        (v, r, s) = _sign(true, alice, false, 2, deadline, whitelisterPk);
        vm.expectRevert(IVaultWhitelistEnterGate.InvalidNonce.selector);
        gate.setIsWhitelistedWithSig(true, alice, false, 2, deadline, v, r, s);

        // wrong domain separator
        (v, r, s) = _sign(true, bob, true, 0, deadline, whitelisterPk);
        VaultWhitelistEnterGate otherGate = _deploy(false, false);
        vm.expectRevert(IVaultWhitelistEnterGate.InvalidSigner.selector);
        otherGate.setIsWhitelistedWithSig(true, bob, true, 0, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigStaleNonceSameValueIsNoop(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(creditSide, account, listed, 0, deadline, v, r, s);

        vm.expectEmit();
        emit IVaultWhitelistEnterGate.SetIsWhitelistedWithSig(
            address(this), whitelister, creditSide, account, listed, 0, 1
        );
        gate.setIsWhitelistedWithSig(creditSide, account, listed, 0, deadline, v, r, s);

        assertEq(gate.isWhitelisted(creditSide, account), listed);
        assertEq(gate.nonces(creditSide, whitelister, account), 1);
    }

    function testSetIsWhitelistedWithSigStaleNonceChecksSignature(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(creditSide, account, listed, 0, deadline, v, r, s);

        // garbage signature
        vm.expectRevert(IVaultWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(creditSide, account, listed, 0, deadline, 0, bytes32(0), bytes32(0));

        // signature from another account
        (v, r, s) = _sign(creditSide, account, listed, 0, deadline, whitelister2Pk);
        vm.expectRevert(IVaultWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(creditSide, account, listed, 0, deadline, v, r, s);

        assertEq(gate.isWhitelisted(creditSide, account), listed);
        assertEq(gate.nonces(creditSide, whitelister, account), 1);
    }

    function testSetIsWhitelistedWithSigStaleNonceDifferentValue(bool creditSide, address account, uint256 deadline)
        public
    {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, true, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(creditSide, account, true, 0, deadline, v, r, s);

        vm.prank(whitelister);
        gate.setIsWhitelisted(creditSide, account, false);

        vm.expectRevert(IVaultWhitelistEnterGate.WhitelistedStatusChanged.selector);
        gate.setIsWhitelistedWithSig(creditSide, account, true, 0, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigFutureNonce(
        bool creditSide,
        address account,
        bool listed,
        uint256 nonce,
        uint256 deadline
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        nonce = bound(nonce, 1, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, nonce, deadline, whitelisterPk);

        vm.expectRevert(IVaultWhitelistEnterGate.InvalidNonce.selector);
        gate.setIsWhitelistedWithSig(creditSide, account, listed, nonce, deadline, v, r, s);
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
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, 0, deadline, whitelisterPk);

        vm.expectRevert(IVaultWhitelistEnterGate.DeadlineExpired.selector);
        gate.setIsWhitelistedWithSig(creditSide, account, listed, 0, deadline, v, r, s);
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
        (uint8 v, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, 0, deadline, wrongPk);

        vm.expectRevert(IVaultWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(creditSide, account, listed, 0, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigEcrecoverReturnsZero(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (, bytes32 r, bytes32 s) = _sign(creditSide, account, listed, 0, deadline, whitelisterPk);

        // Invalid v (valid values are 27/28) -> ecrecover returns address(0).
        vm.expectRevert(IVaultWhitelistEnterGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(creditSide, account, listed, 0, deadline, 0, r, s);
    }

    function testMulticall(address account, bool creditListed, address account2, bool debtListed) public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IVaultWhitelistEnterGate.setIsWhitelisted, (true, account, creditListed));
        data[1] = abi.encodeCall(IVaultWhitelistEnterGate.setIsWhitelisted, (false, account2, debtListed));

        vm.prank(whitelister);
        gate.multicall(data);

        assertEq(gate.isWhitelisted(true, account), creditListed);
        assertEq(gate.isWhitelisted(false, account2), debtListed);
    }

    function testMulticallBubblesRevert(address caller, bool creditSide, address account, bool listed) public {
        vm.assume(caller != whitelister);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(IVaultWhitelistEnterGate.setIsWhitelisted, (creditSide, account, listed));

        // Called by a non-whitelister: the inner call reverts and the multicall must bubble it up.
        vm.expectRevert(IVaultWhitelistEnterGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.multicall(data);
    }

    function testAddWhitelistedAdapterFactory(address factory) public {
        vm.expectEmit();
        emit IVaultWhitelistEnterGate.AddWhitelistedAdapterFactory(factory);
        vm.prank(creditRoleSetter);
        gate.addWhitelistedAdapterFactory(factory);
        assertTrue(gate.isWhitelistedAdapterFactory(factory));

        vm.prank(creditRoleSetter);
        gate.addWhitelistedAdapterFactory(factory);
        assertTrue(gate.isWhitelistedAdapterFactory(factory));
    }

    function testAddWhitelistedAdapterFactoryNotRoleSetter(address caller, address factory) public {
        vm.assume(caller != creditRoleSetter);
        vm.expectRevert(IVaultWhitelistEnterGate.NotRoleSetter.selector);
        vm.prank(caller);
        gate.addWhitelistedAdapterFactory(factory);
    }

    function testAddWhitelistedAdapterFactoryDebtRoleSetter(address factory) public {
        vm.expectRevert(IVaultWhitelistEnterGate.NotRoleSetter.selector);
        vm.prank(debtRoleSetter);
        gate.addWhitelistedAdapterFactory(factory);
    }

    /// forge-config: default.isolate = false
    function testTransientAllowIncreaseCredit(address caller) public {
        _addWhitelistedAdapterFactory();
        _mockTransientAllowance(true, false, address(gate), 1, 1);

        vm.expectEmit();
        emit IVaultWhitelistEnterGate.TransientAllowIncreaseCredit(caller, alice, adapterFactory, adapter, marketId);
        vm.prank(caller);
        gate.transientAllowIncreaseCredit(alice, adapterFactory, adapter, marketId);

        assertTrue(gate.isTransientlyAllowed(alice));
        assertTrue(gate.canIncreaseCredit(alice));
        assertFalse(gate.canIncreaseDebt(alice));
        assertFalse(gate.isTransientlyAllowed(bob));
    }

    function testTransientAllowIncreaseCreditAdapterFactoryNotWhitelisted() public {
        _mockTransientAllowance(true, false, address(gate), 1, 1);

        vm.expectRevert(IVaultWhitelistEnterGate.AdapterFactoryNotWhitelisted.selector);
        gate.transientAllowIncreaseCredit(alice, adapterFactory, adapter, marketId);
        assertFalse(gate.isTransientlyAllowed(alice));
    }

    function testTransientAllowIncreaseCreditNotAdapter() public {
        _addWhitelistedAdapterFactory();
        _mockTransientAllowance(false, false, address(gate), 1, 1);

        vm.expectRevert(IVaultWhitelistEnterGate.NotAdapter.selector);
        gate.transientAllowIncreaseCredit(alice, adapterFactory, adapter, marketId);
        assertFalse(gate.isTransientlyAllowed(alice));
    }

    function testTransientAllowIncreaseCreditAccountIsAdapter() public {
        _addWhitelistedAdapterFactory();
        _mockTransientAllowance(true, true, address(gate), 1, 1);

        vm.expectRevert(IVaultWhitelistEnterGate.AccountIsAdapter.selector);
        gate.transientAllowIncreaseCredit(alice, adapterFactory, adapter, marketId);
        assertFalse(gate.isTransientlyAllowed(alice));
    }

    function testTransientAllowIncreaseCreditIncorrectEnterGate() public {
        _addWhitelistedAdapterFactory();
        _mockTransientAllowance(true, false, address(0x1234), 1, 1);

        vm.expectRevert(IVaultWhitelistEnterGate.IncorrectEnterGate.selector);
        gate.transientAllowIncreaseCredit(alice, adapterFactory, adapter, marketId);
        assertFalse(gate.isTransientlyAllowed(alice));
    }

    function testTransientAllowIncreaseCreditNoAdapterCredit() public {
        _addWhitelistedAdapterFactory();
        _mockTransientAllowance(true, false, address(gate), 0, 1);

        vm.expectRevert(IVaultWhitelistEnterGate.NoAdapterCredit.selector);
        gate.transientAllowIncreaseCredit(alice, adapterFactory, adapter, marketId);
        assertFalse(gate.isTransientlyAllowed(alice));
    }

    function testTransientAllowIncreaseCreditNoVaultShares() public {
        _addWhitelistedAdapterFactory();
        _mockTransientAllowance(true, false, address(gate), 1, 0);

        vm.expectRevert(IVaultWhitelistEnterGate.NoVaultShares.selector);
        gate.transientAllowIncreaseCredit(alice, adapterFactory, adapter, marketId);
        assertFalse(gate.isTransientlyAllowed(alice));
    }

    /// forge-config: default.isolate = true
    function testAuthorizationClearedAfterTransaction() public {
        _addWhitelistedAdapterFactory();
        _mockTransientAllowance(true, false, address(gate), 1, 1);
        this.allowAndCheckUser();
        assertFalse(gate.isTransientlyAllowed(alice));
        assertFalse(gate.canIncreaseCredit(alice));
    }

    function allowAndCheckUser() external {
        gate.transientAllowIncreaseCredit(alice, adapterFactory, adapter, marketId);
        assertTrue(gate.isTransientlyAllowed(alice));
        assertTrue(gate.canIncreaseCredit(alice));
    }

    function testAuthorizationRevertsWithCaller() public {
        _addWhitelistedAdapterFactory();
        _mockTransientAllowance(true, false, address(gate), 1, 1);
        vm.expectRevert(bytes("reverted"));
        this.allowAndRevert();
        assertFalse(gate.isTransientlyAllowed(alice));
        assertFalse(gate.canIncreaseCredit(alice));
    }

    function allowAndRevert() external {
        gate.transientAllowIncreaseCredit(alice, adapterFactory, adapter, marketId);
        revert("reverted");
    }

    function _addWhitelistedAdapterFactory() internal {
        vm.prank(creditRoleSetter);
        gate.addWhitelistedAdapterFactory(adapterFactory);
    }

    function _mockTransientAllowance(
        bool adapterIsAdapter,
        bool accountIsAdapter,
        address enterGate,
        uint128 credit,
        uint256 shares
    ) internal {
        Market memory market;
        market.enterGate = enterGate;
        vm.mockCall(adapterFactory, abi.encodeCall(IMidnightAdapterFactory.midnight, ()), abi.encode(midnight));
        vm.mockCall(
            adapterFactory,
            abi.encodeCall(IMidnightAdapterFactory.isMidnightAdapter, (adapter)),
            abi.encode(adapterIsAdapter)
        );
        vm.mockCall(
            adapterFactory,
            abi.encodeCall(IMidnightAdapterFactory.isMidnightAdapter, (alice)),
            abi.encode(accountIsAdapter)
        );
        vm.mockCall(midnight, abi.encodeCall(IMidnight.toMarket, (marketId)), abi.encode(market));
        vm.mockCall(midnight, abi.encodeCall(IMidnight.credit, (marketId, adapter)), abi.encode(credit));
        vm.mockCall(adapter, abi.encodeCall(IMidnightAdapter.parentVault, ()), abi.encode(vault));
        vm.mockCall(vault, abi.encodeCall(IVault.balanceOf, (alice)), abi.encode(shares));
    }
}

contract VaultWhitelistEnterGateIntegrationTest is BaseTest {
    VaultWhitelistEnterGate internal gate;
    Market internal market;
    Offer internal offer;
    bytes32 internal marketId;
    address internal adapterFactory = makeAddr("integrationAdapterFactory");
    address internal adapter = makeAddr("integrationAdapter");
    address internal depositor = makeAddr("integrationDepositor");

    function setUp() public override {
        super.setUp();

        gate = new VaultWhitelistEnterGate(address(this), address(this), false, true);
        gate.setIsWhitelister(true, address(this), true);
        gate.setIsWhitelisted(true, adapter, true);
        gate.addWhitelistedAdapterFactory(adapterFactory);

        market.loanToken = address(loanToken);
        market.chainId = block.chainid;
        market.midnight = address(midnight);
        market.maturity = vm.getBlockTimestamp() + 100;
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: LLTV,
                    oracle: address(oracle1),
                    liquidationCursor: LIQUIDATION_CURSOR
                })
            );
        market.collateralParams = sortCollateralParams(market.collateralParams);
        market.enterGate = address(gate);
        marketId = toId(market);

        offer.buy = false;
        offer.maker = borrower;
        offer.receiverIfMakerIsSeller = borrower;
        offer.maxUnits = type(uint128).max;
        offer.market = market;
        offer.ratifier = address(dummyRatifier);
        offer.expiry = vm.getBlockTimestamp() + 200;
        offer.tick = MAX_TICK;
        offer.continuousFeeCap = type(uint256).max;

        vm.prank(adapter);
        loanToken.approve(address(midnight), type(uint256).max);
        vm.prank(depositor);
        loanToken.approve(address(midnight), type(uint256).max);
        vm.mockCall(adapterFactory, abi.encodeCall(IMidnightAdapterFactory.midnight, ()), abi.encode(address(midnight)));
        vm.mockCall(
            adapterFactory, abi.encodeCall(IMidnightAdapterFactory.isMidnightAdapter, (adapter)), abi.encode(true)
        );
        vm.mockCall(
            adapterFactory, abi.encodeCall(IMidnightAdapterFactory.isMidnightAdapter, (depositor)), abi.encode(false)
        );
        vm.mockCall(adapter, abi.encodeCall(IMidnightAdapter.parentVault, ()), abi.encode(address(loanToken)));
    }

    /// forge-config: default.isolate = false
    function testTransientAllowIncreaseCreditBypassesGate() public {
        uint256 units = 1;
        collateralize(market, borrower, units * 2);
        deal(address(loanToken), adapter, units);
        deal(address(loanToken), depositor, units);

        take(units, adapter, offer);

        vm.expectRevert(IMidnight.BuyerGatedFromIncreasingCredit.selector);
        take(units, depositor, offer);

        gate.transientAllowIncreaseCredit(depositor, adapterFactory, adapter, marketId);
        take(units, depositor, offer);
    }
}
