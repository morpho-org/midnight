// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {TradingFee} from "../src/interfaces/IMorphoV2.sol";

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

    function testSetObligationTradingFeeSuccess(bytes32 id, bool activated, uint64 min, uint64 halfLife, uint64 max)
        public
    {
        vm.assume(max <= WAD);
        vm.assume(min <= max);

        morphoV2.setObligationTradingFee(id, activated, min, halfLife, max);

        (bool storedActivated, uint64 storedMin, uint64 storedHalfLife, uint64 storedMax) =
            morphoV2.obligationFeesStorage(id);
        assertEq(storedActivated, activated, "activated stored correctly");
        assertEq(storedMin, min, "min stored correctly");
        assertEq(storedHalfLife, halfLife, "halfLife stored correctly");
        assertEq(storedMax, max, "max stored correctly");
    }

    function testSetObligationTradingFeeOnlyFeeSetter(address rdm, bytes32 id) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setObligationTradingFee(id, true, 0, 0, 0);
    }

    function testSetObligationTradingFeeTooHigh(bytes32 id, uint64 max) public {
        vm.assume(max > WAD);
        vm.expectRevert("Trading fee too high");
        morphoV2.setObligationTradingFee(id, true, 0, 1 days, max);
    }

    function testSetObligationTradingFeeMinGreaterThanMax(bytes32 id, uint64 min, uint64 max) public {
        vm.assume(min <= WAD);
        vm.assume(max < min);
        vm.expectRevert("min > max");
        morphoV2.setObligationTradingFee(id, true, min, 1 days, max);
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

    // Default trading fee tests

    function testSetDefaultTradingFeeSuccess(address loanToken, bool activated, uint64 min, uint64 halfLife, uint64 max)
        public
    {
        vm.assume(max <= WAD);
        vm.assume(min <= max);

        morphoV2.setDefaultTradingFee(loanToken, activated, min, halfLife, max);

        (bool storedActivated, uint64 storedMin, uint64 storedHalfLife, uint64 storedMax) =
            morphoV2.defaultFeesStorage(loanToken);
        assertEq(storedActivated, activated, "activated stored correctly");
        assertEq(storedMin, min, "min stored correctly");
        assertEq(storedHalfLife, halfLife, "halfLife stored correctly");
        assertEq(storedMax, max, "max stored correctly");
    }

    function testSetDefaultTradingFeeOnlyFeeSetter(address rdm, address loanToken) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setDefaultTradingFee(loanToken, true, 0, 0, 0);
    }

    function testSetDefaultTradingFeeTooHigh(address loanToken, uint64 max) public {
        vm.assume(max > WAD);
        vm.expectRevert("Trading fee too high");
        morphoV2.setDefaultTradingFee(loanToken, true, 0, 1 days, max);
    }

    function testSetDefaultTradingFeeMinGreaterThanMax(address loanToken, uint64 min, uint64 max) public {
        vm.assume(min <= WAD);
        vm.assume(max < min);
        vm.expectRevert("min > max");
        morphoV2.setDefaultTradingFee(loanToken, true, min, 1 days, max);
    }

    // tradingFee getter tests

    function testTradingFeeReturnsZeroWhenNoneActivated() public {
        bytes32 id = keccak256("test");
        address loanToken = makeAddr("loanToken");

        assertEq(morphoV2.tradingFee(id, loanToken, 0), 0, "should be 0 at t=0");
        assertEq(morphoV2.tradingFee(id, loanToken, 1 days), 0, "should be 0 at t=1day");
        assertEq(morphoV2.tradingFee(id, loanToken, 365 days), 0, "should be 0 at t=1year");
    }

    function testTradingFeeUsesObligationFeeWhenActivated(bytes32 id) public {
        address loanToken = makeAddr("loanToken");
        uint64 oblMin = 0.01e18;
        uint64 oblHalfLife = 7 days;
        uint64 oblMax = 0.05e18;

        uint64 defMin = 0.001e18;
        uint64 defHalfLife = 14 days;
        uint64 defMax = 0.01e18;

        morphoV2.setObligationTradingFee(id, true, oblMin, oblHalfLife, oblMax);
        morphoV2.setDefaultTradingFee(loanToken, true, defMin, defHalfLife, defMax);

        // At t=0, should return obligation min
        assertEq(morphoV2.tradingFee(id, loanToken, 0), oblMin, "should use obligation min at t=0");

        // At halfLife, should use obligation fee formula
        uint256 expectedAtHalfLife = (uint256(oblMax) - uint256(oblMin)) / 2 + uint256(oblMin);
        assertEq(
            morphoV2.tradingFee(id, loanToken, oblHalfLife), expectedAtHalfLife, "should use obligation fee at halfLife"
        );
    }

    function testTradingFeeFallsBackToDefaultWhenObligationNotActivated(bytes32 id) public {
        address loanToken = makeAddr("loanToken");
        uint64 oblMin = 0.01e18;
        uint64 oblHalfLife = 7 days;
        uint64 oblMax = 0.05e18;

        uint64 defMin = 0.001e18;
        uint64 defHalfLife = 14 days;
        uint64 defMax = 0.01e18;

        // Set obligation fee but NOT activated
        morphoV2.setObligationTradingFee(id, false, oblMin, oblHalfLife, oblMax);
        morphoV2.setDefaultTradingFee(loanToken, true, defMin, defHalfLife, defMax);

        // At t=0, should return default min (not obligation min)
        assertEq(morphoV2.tradingFee(id, loanToken, 0), defMin, "should use default min at t=0");

        // At default halfLife, should use default fee formula
        uint256 expectedAtHalfLife = (uint256(defMax) - uint256(defMin)) / 2 + uint256(defMin);
        assertEq(
            morphoV2.tradingFee(id, loanToken, defHalfLife), expectedAtHalfLife, "should use default fee at halfLife"
        );
    }

    function testTradingFeeFormula(bytes32 id) public {
        address loanToken = makeAddr("loanToken");
        uint64 min = 0.01e18;
        uint64 halfLife = 7 days;
        uint64 max = 0.05e18;

        morphoV2.setObligationTradingFee(id, true, min, halfLife, max);

        // At t=0, fee should be min
        assertEq(morphoV2.tradingFee(id, loanToken, 0), min, "fee at t=0 should be min");

        // At t=halfLife, fee should be (max-min)/2 + min
        uint256 expectedAtHalfLife = (uint256(max) - uint256(min)) / 2 + uint256(min);
        assertEq(morphoV2.tradingFee(id, loanToken, halfLife), expectedAtHalfLife, "fee at halfLife");

        // At t=infinity (very large), fee should approach max
        uint256 feeAtLargeT = morphoV2.tradingFee(id, loanToken, 365 days * 100);
        assertGt(feeAtLargeT, (max * 99) / 100, "fee at large t should approach max");
    }

    function testTradingFeeWithZeroHalfLife(bytes32 id) public {
        address loanToken = makeAddr("loanToken");
        uint64 min = 0.01e18;
        uint64 max = 0.05e18;

        morphoV2.setObligationTradingFee(id, true, min, 0, max);

        // With halfLife=0, fee should always return min
        assertEq(morphoV2.tradingFee(id, loanToken, 0), min, "fee at t=0 with halfLife=0");
        assertEq(morphoV2.tradingFee(id, loanToken, 1 days), min, "fee at t=1day with halfLife=0");
        assertEq(morphoV2.tradingFee(id, loanToken, 365 days), min, "fee at t=1year with halfLife=0");
    }

    function testTradingFeeWithZeroHalfLifeDefault(bytes32 id) public {
        address loanToken = makeAddr("loanToken");
        uint64 min = 0.02e18;
        uint64 max = 0.08e18;

        // Obligation fee not activated, default fee with halfLife=0
        morphoV2.setObligationTradingFee(id, false, 0, 0, 0);
        morphoV2.setDefaultTradingFee(loanToken, true, min, 0, max);

        // With halfLife=0, fee should always return min
        assertEq(morphoV2.tradingFee(id, loanToken, 0), min, "default fee at t=0 with halfLife=0");
        assertEq(morphoV2.tradingFee(id, loanToken, 1 days), min, "default fee at t=1day with halfLife=0");
        assertEq(morphoV2.tradingFee(id, loanToken, 365 days), min, "default fee at t=1year with halfLife=0");
    }

    function testTradingFeeMonotonicity(bytes32 id) public {
        address loanToken = makeAddr("loanToken");
        uint64 min = 0.01e18;
        uint64 halfLife = 7 days;
        uint64 max = 0.05e18;

        morphoV2.setObligationTradingFee(id, true, min, halfLife, max);

        uint256 prevFee = morphoV2.tradingFee(id, loanToken, 0);
        uint256[] memory times = new uint256[](10);
        times[0] = 1 days;
        times[1] = 2 days;
        times[2] = 4 days;
        times[3] = 7 days;
        times[4] = 14 days;
        times[5] = 30 days;
        times[6] = 60 days;
        times[7] = 90 days;
        times[8] = 180 days;
        times[9] = 365 days;

        for (uint256 i = 0; i < times.length; i++) {
            uint256 fee = morphoV2.tradingFee(id, loanToken, times[i]);
            assertGe(fee, prevFee, "fee should be monotonically increasing");
            prevFee = fee;
        }
    }
}
