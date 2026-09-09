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
        bytes32 salt
    ) internal view returns (address) {
        // forge-lint: disable-next-item(encode-packed-collision)
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(WhitelistEnterGate).creationCode,
                abi.encode(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen)
            )
        );
        return vm.computeCreate2Address(salt, initCodeHash, address(factory));
    }

    function testCreateWhitelistEnterGate(
        address _creditRoleSetter,
        address _debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 salt
    ) public {
        address expected = _expectedGate(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, salt);

        vm.expectEmit();
        emit IWhitelistEnterGateFactory.CreateWhitelistEnterGate(
            caller, expected, _creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, salt
        );
        vm.prank(caller);
        address gateAddress =
            factory.createWhitelistEnterGate(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, salt);

        assertEq(gateAddress, expected);
        assertTrue(factory.isWhitelistEnterGate(gateAddress));
        WhitelistEnterGate gate = WhitelistEnterGate(gateAddress);
        assertEq(gate.roleSetter(true), _creditRoleSetter);
        assertEq(gate.roleSetter(false), _debtRoleSetter);
        assertEq(gate.CREDIT_OPEN(), creditOpen);
        assertEq(gate.DEBT_OPEN(), debtOpen);
    }

    function testCreateWhitelistEnterGateSameSaltReverts(bytes32 salt) public {
        factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, salt);

        vm.expectRevert();
        factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, salt);
    }

    function testCreateWhitelistEnterGateDifferentSalts(bytes32 salt1, bytes32 salt2) public {
        vm.assume(salt1 != salt2);

        address gate1 = factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, salt1);
        address gate2 = factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, salt2);

        assertTrue(gate1 != gate2);
        assertTrue(factory.isWhitelistEnterGate(gate1));
        assertTrue(factory.isWhitelistEnterGate(gate2));
    }

    function testCreateWhitelistEnterGateDifferentArgs(bytes32 salt) public {
        address gate1 = factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, salt);
        address gate2 = factory.createWhitelistEnterGate(creditRoleSetter, debtRoleSetter, true, false, salt);

        assertTrue(gate1 != gate2);
        assertTrue(factory.isWhitelistEnterGate(gate1));
        assertTrue(factory.isWhitelistEnterGate(gate2));
    }

    function testIsWhitelistEnterGateFalseForUnknownAddress(address account) public view {
        assertFalse(factory.isWhitelistEnterGate(account));
    }
}
