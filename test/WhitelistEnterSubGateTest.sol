// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IEnterGate} from "../src/interfaces/IGate.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {WhitelistEnterSubGate} from "../src/periphery/whitelist-enter-subgate/WhitelistEnterSubGate.sol";
import {
    IWhitelistEnterSubGate,
    SET_IS_WHITELISTED_TYPEHASH,
    EIP712_DOMAIN_TYPEHASH
} from "../src/periphery/whitelist-enter-subgate/interfaces/IWhitelistEnterSubGate.sol";

bytes constant SET_IS_WHITELISTED_TYPE =
    "SetIsWhitelisted(bytes32 marketId,bool creditSide,address account,bool newIsWhitelisted,uint256 nonce,uint256 deadline)";
bytes constant EIP712_DOMAIN_TYPE = "EIP712Domain(uint256 chainId,address verifyingContract)";

contract WhitelistEnterSubGateTest is Test {
    WhitelistEnterSubGate internal gate;
    bytes32 internal marketId = keccak256("market");
    uint256 internal whitelisterPk;
    uint256 internal whitelister2Pk;
    address internal creditRoleSetter = makeAddr("creditRoleSetter");
    address internal debtRoleSetter = makeAddr("debtRoleSetter");
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

    /// @dev Deploys a subgate where whitelister is a whitelister on both sides.
    function _deploy(bool creditOpen, bool debtOpen) internal returns (WhitelistEnterSubGate g) {
        g = new WhitelistEnterSubGate(creditRoleSetter, debtRoleSetter, creditOpen, debtOpen);
        vm.prank(creditRoleSetter);
        g.setIsWhitelister(true, whitelister, true);
        vm.prank(debtRoleSetter);
        g.setIsWhitelister(false, whitelister, true);
    }

    function _roleSetter(bool creditSide) internal view returns (address) {
        return creditSide ? creditRoleSetter : debtRoleSetter;
    }

    function _sign(
        bytes32 _marketId,
        bool creditSide,
        address account,
        bool listed,
        uint256 nonce,
        uint256 deadline,
        uint256 pk
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 hashStruct = keccak256(
            abi.encode(SET_IS_WHITELISTED_TYPEHASH, _marketId, creditSide, account, listed, nonce, deadline)
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

    function testConstructor(address _creditRoleSetter, address _debtRoleSetter, bool creditOpen, bool debtOpen)
        public
    {
        vm.expectEmit();
        emit IWhitelistEnterSubGate.Constructor(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen);
        WhitelistEnterSubGate g = new WhitelistEnterSubGate(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen);
        assertEq(g.roleSetter(true), _creditRoleSetter);
        assertEq(g.roleSetter(false), _debtRoleSetter);
        assertEq(g.CREDIT_OPEN(), creditOpen);
        assertEq(g.DEBT_OPEN(), debtOpen);
        assertFalse(g.isWhitelister(true, _creditRoleSetter));
        assertFalse(g.isWhitelister(false, _debtRoleSetter));
    }

    function testSetRoleSetter(bool creditSide, address newRoleSetter) public {
        vm.expectEmit();
        emit IWhitelistEnterSubGate.SetRoleSetter(creditSide, newRoleSetter);
        vm.prank(_roleSetter(creditSide));
        gate.setRoleSetter(creditSide, newRoleSetter);
        assertEq(gate.roleSetter(creditSide), newRoleSetter);
        // The other side is unaffected.
        assertEq(gate.roleSetter(!creditSide), _roleSetter(!creditSide));
    }

    function testSetRoleSetterNotRoleSetter(address caller, bool creditSide, address newRoleSetter) public {
        vm.assume(caller != _roleSetter(creditSide));
        vm.expectRevert(IWhitelistEnterSubGate.NotRoleSetter.selector);
        vm.prank(caller);
        gate.setRoleSetter(creditSide, newRoleSetter);
    }

    function testRoleSetterCannotSetOtherSideRoleSetter(bool creditSide, address newRoleSetter) public {
        vm.expectRevert(IWhitelistEnterSubGate.NotRoleSetter.selector);
        vm.prank(_roleSetter(!creditSide));
        gate.setRoleSetter(creditSide, newRoleSetter);
    }

    function testSetIsWhitelister(bool creditSide, address account, bool isWhitelister_) public {
        vm.assume(account != whitelister);
        vm.expectEmit();
        emit IWhitelistEnterSubGate.SetIsWhitelister(creditSide, account, isWhitelister_);
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
        vm.expectRevert(IWhitelistEnterSubGate.NotRoleSetter.selector);
        vm.prank(caller);
        gate.setIsWhitelister(creditSide, account, isWhitelister_);
    }

    function testRoleSetterCannotSetOtherSideWhitelister(bool creditSide, address account, bool isWhitelister_) public {
        vm.expectRevert(IWhitelistEnterSubGate.NotRoleSetter.selector);
        vm.prank(_roleSetter(!creditSide));
        gate.setIsWhitelister(creditSide, account, isWhitelister_);
    }

    function testWhitelisterCannotSetIsWhitelister(bool creditSide, address account, bool isWhitelister_) public {
        vm.expectRevert(IWhitelistEnterSubGate.NotRoleSetter.selector);
        vm.prank(whitelister);
        gate.setIsWhitelister(creditSide, account, isWhitelister_);
    }

    function testSetIsWhitelisted(bool creditSide, address account, bool listed) public {
        vm.expectEmit();
        emit IWhitelistEnterSubGate.SetIsWhitelisted(whitelister, marketId, creditSide, account, listed);
        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, creditSide, account, listed);
        assertEq(gate.isWhitelisted(marketId, creditSide, account), listed);
        assertFalse(gate.isWhitelisted(marketId, !creditSide, account));
    }

    function testSetIsWhitelistedNotWhitelister(address caller, bool creditSide, address account, bool listed) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IWhitelistEnterSubGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setIsWhitelisted(marketId, creditSide, account, listed);
    }

    function testWhitelisterCannotSetOtherSideList(bool creditSide, address account, bool listed) public {
        // whitelister2 is a whitelister on creditSide only.
        vm.prank(_roleSetter(creditSide));
        gate.setIsWhitelister(creditSide, whitelister2, true);

        vm.expectRevert(IWhitelistEnterSubGate.NotWhitelister.selector);
        vm.prank(whitelister2);
        gate.setIsWhitelisted(marketId, !creditSide, account, listed);

        vm.prank(whitelister2);
        gate.setIsWhitelisted(marketId, creditSide, account, listed);
        assertEq(gate.isWhitelisted(marketId, creditSide, account), listed);
    }

    function testRevokedWhitelisterCannotSetIsWhitelisted(bool creditSide, address account) public {
        vm.prank(_roleSetter(creditSide));
        gate.setIsWhitelister(creditSide, whitelister, false);

        vm.expectRevert(IWhitelistEnterSubGate.NotWhitelister.selector);
        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, creditSide, account, true);

        // Still a whitelister on the other side.
        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, !creditSide, account, true);
        assertTrue(gate.isWhitelisted(marketId, !creditSide, account));
    }

    function testMultipleWhitelistersCanSetIsWhitelisted(bool creditSide, address account, address account2) public {
        vm.assume(account != account2);

        vm.prank(_roleSetter(creditSide));
        gate.setIsWhitelister(creditSide, whitelister2, true);

        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, creditSide, account, true);
        vm.prank(whitelister2);
        gate.setIsWhitelisted(marketId, creditSide, account2, true);

        assertTrue(gate.isWhitelisted(marketId, creditSide, account));
        assertTrue(gate.isWhitelisted(marketId, creditSide, account2));
    }

    function testCanIncreaseCredit(address account, address other) public {
        vm.assume(account != other);
        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, true, account, true);
        assertTrue(gate.canIncreaseCredit(marketId, account));
        assertFalse(gate.canIncreaseCredit(marketId, other));
    }

    function testCanIncreaseCreditIgnoresDebtList(address account, bool listed) public {
        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, false, account, listed);
        assertFalse(gate.canIncreaseCredit(marketId, account));
    }

    function testCanIncreaseDebt(address account, address other) public {
        vm.assume(account != other);
        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, false, account, true);
        assertTrue(gate.canIncreaseDebt(marketId, account));
        assertFalse(gate.canIncreaseDebt(marketId, other));
    }

    function testCanIncreaseDebtIgnoresCreditList(address account, bool listed) public {
        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, true, account, listed);
        assertFalse(gate.canIncreaseDebt(marketId, account));
    }

    function testSidesAreIndependent(address account, bool creditListed, bool debtListed) public {
        vm.startPrank(whitelister);
        gate.setIsWhitelisted(marketId, true, account, creditListed);
        gate.setIsWhitelisted(marketId, false, account, debtListed);
        vm.stopPrank();
        assertEq(gate.isWhitelisted(marketId, true, account), creditListed);
        assertEq(gate.isWhitelisted(marketId, false, account), debtListed);
        assertEq(gate.canIncreaseCredit(marketId, account), creditListed);
        assertEq(gate.canIncreaseDebt(marketId, account), debtListed);
    }

    function testOpenCreditSideLetsAnyoneIn(address account, address other) public {
        vm.assume(account != other);
        gate = _deploy(true, false);
        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, false, account, true);

        assertTrue(gate.canIncreaseCredit(marketId, account));
        assertTrue(gate.canIncreaseCredit(marketId, other));
        // The debt side still honours its whitelist.
        assertTrue(gate.canIncreaseDebt(marketId, account));
        assertFalse(gate.canIncreaseDebt(marketId, other));
    }

    function testOpenDebtSideLetsAnyoneIn(address account, address other) public {
        vm.assume(account != other);
        gate = _deploy(false, true);
        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, true, account, true);

        assertTrue(gate.canIncreaseDebt(marketId, account));
        assertTrue(gate.canIncreaseDebt(marketId, other));
        // The credit side still honours its whitelist.
        assertTrue(gate.canIncreaseCredit(marketId, account));
        assertFalse(gate.canIncreaseCredit(marketId, other));
    }

    function testOpenSideIgnoresWhitelist(bool creditSide, address account, bool whitelisted) public {
        gate = _deploy(creditSide, !creditSide);
        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, creditSide, account, whitelisted);
        assertTrue(creditSide ? gate.canIncreaseCredit(marketId, account) : gate.canIncreaseDebt(marketId, account));
    }

    function testSetIsWhitelistedWithSig(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline,
        address relayer
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, listed, 0, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistEnterSubGate.SetIsWhitelistedWithSig(
            relayer, whitelister, marketId, creditSide, account, listed, 0, 0
        );
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, listed, 0, deadline, v, r, s);

        assertEq(gate.isWhitelisted(marketId, creditSide, account), listed);
        assertFalse(gate.isWhitelisted(marketId, !creditSide, account));
        assertEq(gate.nonces(marketId, creditSide, whitelister, account), 1);
    }

    function testSetIsWhitelistedWithSigRejectsOtherSide(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, listed, 0, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistEnterSubGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(marketId, !creditSide, account, listed, 0, deadline, v, r, s);
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
        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, listed, 0, deadline, whitelister2Pk);

        vm.expectRevert(IWhitelistEnterSubGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, listed, 0, deadline, v, r, s);
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
        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, listed, 0, deadline, whitelister2Pk);

        vm.expectEmit();
        emit IWhitelistEnterSubGate.SetIsWhitelistedWithSig(
            relayer, whitelister2, marketId, creditSide, account, listed, 0, 0
        );
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, listed, 0, deadline, v, r, s);

        assertEq(gate.isWhitelisted(marketId, creditSide, account), listed);
        assertEq(gate.nonces(marketId, creditSide, whitelister2, account), 1);
    }

    function testNoncesArePerWhitelister(bool creditSide, address account, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(_roleSetter(creditSide));
        gate.setIsWhitelister(creditSide, whitelister2, true);

        // Both whitelisters sign for the same account at their own nonce 0.
        (uint8 v1, bytes32 r1, bytes32 s1) = _sign(marketId, creditSide, account, true, 0, deadline, whitelisterPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _sign(marketId, creditSide, account, true, 0, deadline, whitelister2Pk);

        gate.setIsWhitelistedWithSig(marketId, creditSide, account, true, 0, deadline, v1, r1, s1);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, true, 0, deadline, v2, r2, s2);

        assertEq(gate.nonces(marketId, creditSide, whitelister, account), 1);
        assertEq(gate.nonces(marketId, creditSide, whitelister2, account), 1);
    }

    function testNoncesArePerSide(bool creditSide, address account, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);

        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, true, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, true, 0, deadline, v, r, s);
        assertEq(gate.nonces(marketId, creditSide, whitelister, account), 1);
        assertEq(gate.nonces(marketId, !creditSide, whitelister, account), 0);

        // The other side signature still uses nonce 0.
        (v, r, s) = _sign(marketId, !creditSide, account, true, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(marketId, !creditSide, account, true, 0, deadline, v, r, s);
        assertEq(gate.nonces(marketId, creditSide, whitelister, account), 1);
        assertEq(gate.nonces(marketId, !creditSide, whitelister, account), 1);
    }

    function testSetIsWhitelistedWithSigRejectsRevokedWhitelister(bool creditSide, address account, bool listed)
        public
    {
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, listed, 0, deadline, whitelisterPk);

        vm.prank(_roleSetter(creditSide));
        gate.setIsWhitelister(creditSide, whitelister, false);

        vm.expectRevert(IWhitelistEnterSubGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, listed, 0, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigRejectsReplayAndTampering() public {
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, true, alice, true, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(marketId, true, alice, true, 0, deadline, v, r, s);
        assertEq(gate.nonces(marketId, true, whitelister, alice), 1);

        // replay is a no-op
        gate.setIsWhitelistedWithSig(marketId, true, alice, true, 0, deadline, v, r, s);
        assertEq(gate.nonces(marketId, true, whitelister, alice), 1);

        // wrong side
        (v, r, s) = _sign(marketId, true, alice, false, 0, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterSubGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(marketId, false, alice, false, 0, deadline, v, r, s);

        // wrong account
        (v, r, s) = _sign(marketId, true, alice, false, 0, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterSubGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(marketId, true, bob, false, 0, deadline, v, r, s);

        // wrong value
        (v, r, s) = _sign(marketId, true, alice, false, 1, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterSubGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(marketId, true, alice, true, 1, deadline, v, r, s);

        // wrong deadline
        (v, r, s) = _sign(marketId, true, alice, false, 1, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterSubGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(marketId, true, alice, false, 1, deadline + 1, v, r, s);

        // wrong nonce
        (v, r, s) = _sign(marketId, true, alice, false, 2, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistEnterSubGate.InvalidNonce.selector);
        gate.setIsWhitelistedWithSig(marketId, true, alice, false, 2, deadline, v, r, s);

        // wrong domain separator
        (v, r, s) = _sign(marketId, true, bob, true, 0, deadline, whitelisterPk);
        WhitelistEnterSubGate otherGate = _deploy(false, false);
        vm.expectRevert(IWhitelistEnterSubGate.InvalidSigner.selector);
        otherGate.setIsWhitelistedWithSig(marketId, true, bob, true, 0, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigStaleNonceSameValueIsNoop(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, listed, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, listed, 0, deadline, v, r, s);

        vm.expectEmit();
        emit IWhitelistEnterSubGate.SetIsWhitelistedWithSig(
            address(this), whitelister, marketId, creditSide, account, listed, 0, 1
        );
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, listed, 0, deadline, v, r, s);

        assertEq(gate.isWhitelisted(marketId, creditSide, account), listed);
        assertEq(gate.nonces(marketId, creditSide, whitelister, account), 1);
    }

    function testSetIsWhitelistedWithSigStaleNonceChecksSignature(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, listed, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, listed, 0, deadline, v, r, s);

        // garbage signature
        vm.expectRevert(IWhitelistEnterSubGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, listed, 0, deadline, 0, bytes32(0), bytes32(0));

        // signature from another account
        (v, r, s) = _sign(marketId, creditSide, account, listed, 0, deadline, whitelister2Pk);
        vm.expectRevert(IWhitelistEnterSubGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, listed, 0, deadline, v, r, s);

        assertEq(gate.isWhitelisted(marketId, creditSide, account), listed);
        assertEq(gate.nonces(marketId, creditSide, whitelister, account), 1);
    }

    function testSetIsWhitelistedWithSigStaleNonceDifferentValue(bool creditSide, address account, uint256 deadline)
        public
    {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, true, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, true, 0, deadline, v, r, s);

        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, creditSide, account, false);

        vm.expectRevert(IWhitelistEnterSubGate.WhitelistedStatusChanged.selector);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, true, 0, deadline, v, r, s);
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
        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, listed, nonce, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistEnterSubGate.InvalidNonce.selector);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, listed, nonce, deadline, v, r, s);
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
        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, listed, 0, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistEnterSubGate.DeadlineExpired.selector);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, listed, 0, deadline, v, r, s);
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
        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, listed, 0, deadline, wrongPk);

        vm.expectRevert(IWhitelistEnterSubGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, listed, 0, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigEcrecoverReturnsZero(
        bool creditSide,
        address account,
        bool listed,
        uint256 deadline
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, listed, 0, deadline, whitelisterPk);

        // Invalid v (valid values are 27/28) -> ecrecover returns address(0).
        vm.expectRevert(IWhitelistEnterSubGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, listed, 0, deadline, 0, r, s);
    }

    function testMarketsAreIndependent(bytes32 otherMarketId, address account, bool creditSide) public {
        vm.assume(otherMarketId != marketId);
        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, creditSide, account, true);

        assertTrue(gate.isWhitelisted(marketId, creditSide, account));
        assertFalse(gate.isWhitelisted(otherMarketId, creditSide, account));
        assertEq(gate.canIncreaseCredit(marketId, account), creditSide);
        assertEq(gate.canIncreaseDebt(marketId, account), !creditSide);
        assertFalse(gate.canIncreaseCredit(otherMarketId, account));
        assertFalse(gate.canIncreaseDebt(otherMarketId, account));

        vm.startPrank(whitelister);
        gate.setIsWhitelisted(otherMarketId, creditSide, account, true);
        gate.setIsWhitelisted(marketId, creditSide, account, false);
        vm.stopPrank();
        assertFalse(gate.isWhitelisted(marketId, creditSide, account));
        assertTrue(gate.isWhitelisted(otherMarketId, creditSide, account));
    }

    function testNoncesArePerMarket(bytes32 otherMarketId, bool creditSide, address account) public {
        vm.assume(otherMarketId != marketId);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, true, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, true, 0, deadline, v, r, s);
        assertEq(gate.nonces(marketId, creditSide, whitelister, account), 1);
        assertEq(gate.nonces(otherMarketId, creditSide, whitelister, account), 0);

        (v, r, s) = _sign(otherMarketId, creditSide, account, true, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(otherMarketId, creditSide, account, true, 0, deadline, v, r, s);
        assertEq(gate.nonces(marketId, creditSide, whitelister, account), 1);
        assertEq(gate.nonces(otherMarketId, creditSide, whitelister, account), 1);
    }

    function testSetIsWhitelistedWithSigRejectsOtherMarket(bytes32 otherMarketId, bool creditSide, address account)
        public
    {
        vm.assume(otherMarketId != marketId);
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _sign(marketId, creditSide, account, true, 0, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(marketId, creditSide, account, true, 0, deadline, v, r, s);

        vm.expectRevert(IWhitelistEnterSubGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(otherMarketId, creditSide, account, true, 0, deadline, v, r, s);
        assertFalse(gate.isWhitelisted(otherMarketId, creditSide, account));
        assertEq(gate.nonces(otherMarketId, creditSide, whitelister, account), 0);
    }

    function testWhitelisterRevocationAppliesToEveryMarket(bytes32 otherMarketId, bool creditSide, address account)
        public
    {
        vm.assume(otherMarketId != marketId);
        vm.startPrank(whitelister);
        gate.setIsWhitelisted(marketId, creditSide, account, true);
        gate.setIsWhitelisted(otherMarketId, creditSide, account, true);
        vm.stopPrank();
        vm.prank(_roleSetter(creditSide));
        gate.setIsWhitelister(creditSide, whitelister, false);

        vm.expectRevert(IWhitelistEnterSubGate.NotWhitelister.selector);
        vm.prank(whitelister);
        gate.setIsWhitelisted(marketId, creditSide, account, false);
        vm.expectRevert(IWhitelistEnterSubGate.NotWhitelister.selector);
        vm.prank(whitelister);
        gate.setIsWhitelisted(otherMarketId, creditSide, account, false);
        assertTrue(gate.isWhitelisted(marketId, creditSide, account));
        assertTrue(gate.isWhitelisted(otherMarketId, creditSide, account));
    }

    function testOpenSidesApplyToEveryMarket(bytes32 otherMarketId, address account, bool creditOpen, bool debtOpen)
        public
    {
        vm.assume(otherMarketId != marketId);
        gate = _deploy(creditOpen, debtOpen);
        assertEq(gate.canIncreaseCredit(marketId, account), creditOpen);
        assertEq(gate.canIncreaseCredit(otherMarketId, account), creditOpen);
        assertEq(gate.canIncreaseDebt(marketId, account), debtOpen);
        assertEq(gate.canIncreaseDebt(otherMarketId, account), debtOpen);
    }

    function testCannotUseAsEnterGate(address account) public {
        gate = _deploy(true, true);
        assertTrue(gate.canIncreaseCredit(marketId, account));
        assertTrue(gate.canIncreaseDebt(marketId, account));

        vm.expectRevert();
        IEnterGate(address(gate)).canIncreaseCredit(account);
        vm.expectRevert();
        IEnterGate(address(gate)).canIncreaseDebt(account);
    }

    function testMulticall(address account, bool creditListed, address account2, bool debtListed) public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IWhitelistEnterSubGate.setIsWhitelisted, (marketId, true, account, creditListed));
        data[1] = abi.encodeCall(IWhitelistEnterSubGate.setIsWhitelisted, (marketId, false, account2, debtListed));

        vm.prank(whitelister);
        gate.multicall(data);

        assertEq(gate.isWhitelisted(marketId, true, account), creditListed);
        assertEq(gate.isWhitelisted(marketId, false, account2), debtListed);
    }

    function testMulticallBubblesRevert(address caller, bool creditSide, address account, bool listed) public {
        vm.assume(caller != whitelister);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(IWhitelistEnterSubGate.setIsWhitelisted, (marketId, creditSide, account, listed));

        // Called by a non-whitelister: the inner call reverts and the multicall must bubble it up.
        vm.expectRevert(IWhitelistEnterSubGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.multicall(data);
    }
}
