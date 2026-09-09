// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {WhitelistEnterGate} from "../src/periphery/whitelist-enter-gate/WhitelistEnterGate.sol";
import {WhitelistEnterGateFactory} from "../src/periphery/whitelist-enter-gate/WhitelistEnterGateFactory.sol";
import {
    IWhitelistEnterGateFactory
} from "../src/periphery/whitelist-enter-gate/interfaces/IWhitelistEnterGateFactory.sol";

contract WhitelistEnterGateFactoryTest is Test {
    WhitelistEnterGateFactory internal factory;
    address internal caller = makeAddr("caller");
    address internal creditRoleSetter = makeAddr("creditRoleSetter");
    address internal debtRoleSetter = makeAddr("debtRoleSetter");

    function setUp() public {
        factory = new WhitelistEnterGateFactory();
    }

    function _expectedGate(
        address _creditRoleSetter,
        address _debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt,
        address _caller
    ) internal view returns (address) {
        // forge-lint: disable-next-item(encode-packed-collision)
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(WhitelistEnterGate).creationCode,
                abi.encode(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen)
            )
        );
        return vm.computeCreate2Address(keccak256(abi.encode(preSalt, _caller)), initCodeHash, address(factory));
    }

    function testCreateWhitelistEnterGate(
        address _creditRoleSetter,
        address _debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt
    ) public {
        address expected = _expectedGate(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, preSalt, caller);

        vm.expectEmit();
        emit IWhitelistEnterGateFactory.CreateWhitelistEnterGate(
            caller, expected, _creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, preSalt
        );
        vm.prank(caller);
        address gateAddress =
            factory.createWhitelistEnterGate(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, preSalt);

        assertEq(gateAddress, expected);
        assertTrue(factory.isWhitelistEnterGate(gateAddress));
        WhitelistEnterGate gate = WhitelistEnterGate(gateAddress);
        assertEq(gate.roleSetter(true), _creditRoleSetter);
        assertEq(gate.roleSetter(false), _debtRoleSetter);
        assertEq(gate.CREDIT_OPEN(), creditOpen);
        assertEq(gate.DEBT_OPEN(), debtOpen);
    }

    function testCreateWhitelistEnterGateSamePreSaltReverts(bytes32 preSalt) public {
        factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);

        vm.expectRevert();
        factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);
    }

    function testCreateWhitelistEnterGateDifferentCallers(bytes32 preSalt, address caller1, address caller2) public {
        vm.assume(caller1 != caller2);

        vm.prank(caller1);
        address gate1 = factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);
        vm.prank(caller2);
        address gate2 = factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);

        assertEq(gate1, _expectedGate(creditRoleSetter, debtRoleSetter, false, false, preSalt, caller1));
        assertEq(gate2, _expectedGate(creditRoleSetter, debtRoleSetter, false, false, preSalt, caller2));
        assertTrue(gate1 != gate2);
        assertTrue(factory.isWhitelistEnterGate(gate1));
        assertTrue(factory.isWhitelistEnterGate(gate2));
    }

    function testCreateWhitelistEnterGateDifferentPreSalts(bytes32 preSalt1, bytes32 preSalt2) public {
        vm.assume(preSalt1 != preSalt2);

        address gate1 = factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt1);
        address gate2 = factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt2);

        assertTrue(gate1 != gate2);
        assertTrue(factory.isWhitelistEnterGate(gate1));
        assertTrue(factory.isWhitelistEnterGate(gate2));
    }

    function testCreateWhitelistEnterGateDifferentArgs(bytes32 preSalt) public {
        address gate1 = factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);
        address gate2 = factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, true, false, preSalt);

        assertTrue(gate1 != gate2);
        assertTrue(factory.isWhitelistEnterGate(gate1));
        assertTrue(factory.isWhitelistEnterGate(gate2));
    }

    function testIsWhitelistEnterGateFalseForUnknownAddress(address account) public view {
        assertFalse(factory.isWhitelistEnterGate(account));
    }
}
