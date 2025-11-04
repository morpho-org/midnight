// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";

contract SettersTest is BaseTest {
    function testInitialOwner() public view {
        assertEq(morphoV2.owner(), address(this), "deployer should be initial owner");
    }

    function testSetOwnerSuccess(address rdm) public {
        morphoV2.setOwner(rdm);
        assertEq(morphoV2.owner(), rdm, "owner should be transferred");
    }

    function testSetOwnerOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setOwner(makeAddr("newOwner"));
    }

    function testSetFeeSetterSuccess(address feeSetter) public {
        morphoV2.setFeeSetter(feeSetter);
        assertEq(morphoV2.feeSetter(), feeSetter);
    }

    function testSetFeeSetterOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setFeeSetter(makeAddr("newFeeSetter"));
    }

    function testSetTradingFeeSuccess(bytes32 id, uint64 sellTradingFee, uint64 sellInterestCutLimit, uint64 buyTradingFee, uint64 buyInterestCutLimit) public {
        vm.assume(sellTradingFee <= WAD);
        vm.assume(sellInterestCutLimit <= WAD);
        vm.assume(buyTradingFee <= WAD);
        vm.assume(buyInterestCutLimit <= WAD);
        morphoV2.setTradingFee(id, sellTradingFee, sellInterestCutLimit, buyTradingFee, buyInterestCutLimit);
        (uint64 _sellTradingFee, uint64 _sellInterestCutLimit, uint64 _buyTradingFee, uint64 _buyInterestCutLimit) = morphoV2.tradingFeeParams(id);
        assertEq(_sellTradingFee, sellTradingFee);
        assertEq(_sellInterestCutLimit, sellInterestCutLimit);
        assertEq(_buyTradingFee, buyTradingFee);
        assertEq(_buyInterestCutLimit, buyInterestCutLimit);
    }

    function testSetTradingFeeOnlyFeeSetter(address rdm, bytes32 id) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setTradingFee(id, 0.1e18, 0.1e18, 0.1e18, 0.1e18);
    }

    function testSetTradingFeeRecipientSuccess(address recipient) public {
        morphoV2.setTradingFeeRecipient(recipient);
        assertEq(morphoV2.tradingFeeRecipient(), recipient, "recipient set");
    }

    function testSetTradingFeeRecipientOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setTradingFeeRecipient(makeAddr("newRecipient"));
    }
}
