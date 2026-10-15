// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {VaultWhitelistEnterGate} from "../src/periphery/vault-whitelist-enter-gate/VaultWhitelistEnterGate.sol";
import {
    VaultWhitelistEnterGateFactory
} from "../src/periphery/vault-whitelist-enter-gate/VaultWhitelistEnterGateFactory.sol";
import {
    IVaultWhitelistEnterGateFactory
} from "../src/periphery/vault-whitelist-enter-gate/interfaces/IVaultWhitelistEnterGateFactory.sol";

contract VaultWhitelistEnterGateFactoryTest is Test {
    VaultWhitelistEnterGateFactory internal factory;
    address internal caller = makeAddr("caller");
    address internal creditRoleSetter = makeAddr("creditRoleSetter");
    address internal debtRoleSetter = makeAddr("debtRoleSetter");

    function setUp() public {
        factory = new VaultWhitelistEnterGateFactory();
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
                type(VaultWhitelistEnterGate).creationCode,
                abi.encode(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen)
            )
        );
        return vm.computeCreate2Address(keccak256(abi.encode(preSalt, _caller)), initCodeHash, address(factory));
    }

    function testCreateVaultWhitelistEnterGate(
        address _creditRoleSetter,
        address _debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt
    ) public {
        address expected = _expectedGate(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, preSalt, caller);

        vm.expectEmit();
        emit IVaultWhitelistEnterGateFactory.CreateVaultWhitelistEnterGate(
            caller, expected, _creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, preSalt
        );
        vm.prank(caller);
        address gateAddress =
            factory.createVaultWhitelistEnterGate(_creditRoleSetter, _debtRoleSetter, creditOpen, debtOpen, preSalt);

        assertEq(gateAddress, expected);
        assertTrue(factory.isVaultWhitelistEnterGate(gateAddress));
        VaultWhitelistEnterGate gate = VaultWhitelistEnterGate(gateAddress);
        assertEq(gate.roleSetter(true), _creditRoleSetter);
        assertEq(gate.roleSetter(false), _debtRoleSetter);
        assertEq(gate.CREDIT_OPEN(), creditOpen);
        assertEq(gate.DEBT_OPEN(), debtOpen);
    }

    function testCreateVaultWhitelistEnterGateSamePreSaltReverts(bytes32 preSalt) public {
        factory.createVaultWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);

        vm.expectRevert();
        factory.createVaultWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);
    }

    function testCreateVaultWhitelistEnterGateDifferentCallers(bytes32 preSalt, address caller1, address caller2)
        public
    {
        vm.assume(caller1 != caller2);

        vm.prank(caller1);
        address gate1 = factory.createVaultWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);
        vm.prank(caller2);
        address gate2 = factory.createVaultWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);

        assertEq(gate1, _expectedGate(creditRoleSetter, debtRoleSetter, false, false, preSalt, caller1));
        assertEq(gate2, _expectedGate(creditRoleSetter, debtRoleSetter, false, false, preSalt, caller2));
        assertTrue(gate1 != gate2);
        assertTrue(factory.isVaultWhitelistEnterGate(gate1));
        assertTrue(factory.isVaultWhitelistEnterGate(gate2));
    }

    function testCreateVaultWhitelistEnterGateDifferentPreSalts(bytes32 preSalt1, bytes32 preSalt2) public {
        vm.assume(preSalt1 != preSalt2);

        address gate1 = factory.createVaultWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt1);
        address gate2 = factory.createVaultWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt2);

        assertTrue(gate1 != gate2);
        assertTrue(factory.isVaultWhitelistEnterGate(gate1));
        assertTrue(factory.isVaultWhitelistEnterGate(gate2));
    }

    function testCreateVaultWhitelistEnterGateDifferentArgs(bytes32 preSalt) public {
        address gate1 = factory.createVaultWhitelistEnterGate(creditRoleSetter, debtRoleSetter, false, false, preSalt);
        address gate2 = factory.createVaultWhitelistEnterGate(creditRoleSetter, debtRoleSetter, true, false, preSalt);

        assertTrue(gate1 != gate2);
        assertTrue(factory.isVaultWhitelistEnterGate(gate1));
        assertTrue(factory.isVaultWhitelistEnterGate(gate2));
    }

    function testIsVaultWhitelistEnterGateFalseForUnknownAddress(address account) public view {
        assertFalse(factory.isVaultWhitelistEnterGate(account));
    }
}
