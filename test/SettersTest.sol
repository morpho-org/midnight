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

    function testSetTradingFeeSuccess(bytes32 id, uint128 tradingFee, uint128 interestCutLimit) public {
        vm.assume(tradingFee <= WAD);
        vm.assume(interestCutLimit < WAD);
        morphoV2.setTradingFee(id, tradingFee, interestCutLimit);
        (uint128 _tradingFee, uint128 _interestCutLimit) = morphoV2.tradingFeeParams(id);
        assertEq(_tradingFee, tradingFee);
        assertEq(_interestCutLimit, interestCutLimit);
    }

    function testSetTradingFeeOnlyFeeSetter(address rdm, bytes32 id) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setTradingFee(id, 0.1e18, 0.1e18);
    }

    function testSetInterestCutLimitTooHigh(bytes32 id, uint256 interestCutLimit) public {
        vm.assume(interestCutLimit >= WAD);
        vm.expectRevert("Interest cut limit too high");
        morphoV2.setTradingFee(id, 0.1e18, interestCutLimit);
    }

    function testSetTradingFeeTooHigh(bytes32 id, uint256 tradingFee) public {
        vm.assume(tradingFee > type(uint128).max);
        vm.expectRevert("Trading fee too high");
        morphoV2.setTradingFee(id, tradingFee, 0.1e18);
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
