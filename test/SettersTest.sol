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

    function testSetTradingFeeSuccess(bytes32 id, uint256 minTradingFee, uint256 maxTradingFee, uint256 slope) public {
        vm.assume(minTradingFee <= type(uint64).max);
        vm.assume(maxTradingFee <= type(uint64).max);
        vm.assume(slope <= WAD);
        morphoV2.setTradingFee(id, minTradingFee, maxTradingFee, slope);
        (uint64 _minTradingFee, uint64 _maxTradingFee, uint64 _slope) = morphoV2.tradingFeeParams(id);
        assertEq(_minTradingFee, minTradingFee);
        assertEq(_maxTradingFee, maxTradingFee);
        assertEq(_slope, slope);
    }

    function testSetTradingFeeOnlyFeeSetter(address rdm, bytes32 id) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setTradingFee(id, 0.1e18, 0, 0);
    }

    function testSetSlopeTooHigh(bytes32 id, uint256 slope) public {
        vm.assume(slope > type(uint64).max);
        vm.expectRevert("Slope too high");
        morphoV2.setTradingFee(id, 0, 0, slope);
    }

    function testSetMinTradingFeeTooHigh(bytes32 id, uint256 tradingFee) public {
        vm.assume(tradingFee > type(uint64).max);
        vm.expectRevert("Min trading fee too high");
        morphoV2.setTradingFee(id, tradingFee, 0, 0);
    }

    function testSetMaxTradingFeeTooHigh(bytes32 id, uint256 tradingFee) public {
        vm.assume(tradingFee > type(uint64).max);
        vm.expectRevert("Max trading fee too high");
        morphoV2.setTradingFee(id, 0, tradingFee, 0);
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
