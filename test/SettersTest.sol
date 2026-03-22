// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {Obligation, Collateral} from "../src/interfaces/IMidnight.sol";

contract SettersTest is BaseTest {
    function testInitialOwner() public view {
        assertEq(midnight.owner(), address(this), "deployer should be initial owner");
    }

    function testSetOwnerSuccess(address rdm) public {
        midnight.setOwner(rdm);
        assertEq(midnight.owner(), rdm, "owner should be transferred");
    }

    function testSetOwnerOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("only owner");
        midnight.setOwner(makeAddr("newOwner"));
    }

    function testSetFeeSetterSuccess(address feeSetter) public {
        midnight.setFeeSetter(feeSetter);
        assertEq(midnight.feeSetter(), feeSetter);
    }

    function testSetFeeSetterOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("only owner");
        midnight.setFeeSetter(makeAddr("newFeeSetter"));
    }

    function testSetTradingFeeSuccess(
        address loanToken,
        uint256 postMaturityFee,
        uint256 oneDayFee,
        uint256 sevenDaysFee,
        uint256 thirtyDaysFee,
        uint256 ninetyDaysFee,
        uint256 oneEightyDaysFee,
        uint256 threeSixtyDaysFee
    ) public {
        postMaturityFee = bound(postMaturityFee, 0, midnight.maxTradingFee(0)) / 1e12 * 1e12;
        oneDayFee = bound(oneDayFee, 0, midnight.maxTradingFee(1)) / 1e12 * 1e12;
        sevenDaysFee = bound(sevenDaysFee, 0, midnight.maxTradingFee(2)) / 1e12 * 1e12;
        thirtyDaysFee = bound(thirtyDaysFee, 0, midnight.maxTradingFee(3)) / 1e12 * 1e12;
        ninetyDaysFee = bound(ninetyDaysFee, 0, midnight.maxTradingFee(4)) / 1e12 * 1e12;
        oneEightyDaysFee = bound(oneEightyDaysFee, 0, midnight.maxTradingFee(5)) / 1e12 * 1e12;
        threeSixtyDaysFee = bound(threeSixtyDaysFee, 0, midnight.maxTradingFee(6)) / 1e12 * 1e12;

        Collateral[] memory collaterals = new Collateral[](1);
        collaterals[0] = Collateral({
            token: address(collateralToken1), lltv: 0.75e18, maxLif: maxLif(0.75e18, 0.25e18), oracle: address(oracle1)
        });
        Obligation memory obligation = Obligation({
            loanToken: loanToken,
            maturity: block.timestamp + 1 days,
            collaterals: collaterals,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        bytes32 id = toId(obligation);
        midnight.touchObligation(obligation);

        midnight.setObligationTradingFee(id, 0, postMaturityFee);
        midnight.setObligationTradingFee(id, 1, oneDayFee);
        midnight.setObligationTradingFee(id, 2, sevenDaysFee);
        midnight.setObligationTradingFee(id, 3, thirtyDaysFee);
        midnight.setObligationTradingFee(id, 4, ninetyDaysFee);
        midnight.setObligationTradingFee(id, 5, oneEightyDaysFee);
        midnight.setObligationTradingFee(id, 6, threeSixtyDaysFee);

        assertEq(midnight.tradingFee(id, 0), postMaturityFee, "post maturity trading fee");
        assertEq(midnight.tradingFee(id, 1 days), oneDayFee, "one day trading fee");
        assertEq(midnight.tradingFee(id, 7 days), sevenDaysFee, "seven days trading fee");
        assertEq(midnight.tradingFee(id, 30 days), thirtyDaysFee, "thirty days trading fee");
        assertEq(midnight.tradingFee(id, 90 days), ninetyDaysFee, "ninety days trading fee");
        assertEq(midnight.tradingFee(id, 180 days), oneEightyDaysFee, "one eighty days trading fee");
        assertEq(midnight.tradingFee(id, 360 days), threeSixtyDaysFee, "three sixty days trading fee");
        assertEq(midnight.tradingFee(id, 365 days), threeSixtyDaysFee, "three sixty five days trading fee");
        assertEq(midnight.tradingFee(id, 1000 days), threeSixtyDaysFee, "one thousand days trading fee");
    }

    function testSetTradingFeeInvalidIndex(bytes32 id) public {
        vm.expectRevert("invalid index");
        midnight.setObligationTradingFee(id, 7, 0);
    }

    function testSetDefaultTradingFeeInvalidIndex(address loanToken) public {
        vm.expectRevert("invalid index");
        midnight.setDefaultTradingFee(loanToken, 7, 0);
    }

    function testSetObligationTradingFeeValueTooHigh(bytes32 id, uint256 feeTooHigh, uint256 index) public {
        index = bound(index, 0, 6);
        feeTooHigh = bound(feeTooHigh, midnight.maxTradingFee(index) + 1, 1e18);
        vm.expectRevert("value too high");
        midnight.setObligationTradingFee(id, index, feeTooHigh);
    }

    function testSetTradingFeeNotMultipleOfFeeStep(bytes32 id, uint256 index, uint256 fee) public {
        index = bound(index, 0, 6);
        fee = bound(fee, 1, midnight.maxTradingFee(index));
        vm.assume(fee % 1e12 != 0);
        vm.expectRevert("fee should be a multiple of FEE_STEP");
        midnight.setObligationTradingFee(id, index, fee);
    }

    function testSetDefaultTradingFeeNotMultipleOfFeeStep(address loanToken, uint256 index, uint256 fee) public {
        index = bound(index, 0, 6);
        fee = bound(fee, 1, midnight.maxTradingFee(index));
        vm.assume(fee % 1e12 != 0);
        vm.expectRevert("fee should be a multiple of FEE_STEP");
        midnight.setDefaultTradingFee(loanToken, index, fee);
    }

    function testSetObligationTradingFeeObligationNotCreated(bytes32 id) public {
        vm.expectRevert("obligation not created");
        midnight.setObligationTradingFee(id, 0, 0);
    }

    function testSetTradingFeeOnlyFeeSetter(address rdm, bytes32 id) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("only fee setter");
        midnight.setObligationTradingFee(id, 0, 0);
    }

    function testSetTradingFeeRecipientSuccess(address feeRecipient) public {
        midnight.setTradingFeeRecipient(feeRecipient);
        assertEq(midnight.tradingFeeRecipient(), feeRecipient, "fee recipient set");
    }

    function testSetTradingFeeRecipientOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("only owner");
        midnight.setTradingFeeRecipient(makeAddr("newRecipient"));
    }

    // Default trading fee tests

    function testTradingFeeRevertsWhenNotCreated() public {
        vm.expectRevert("not created");
        midnight.tradingFee(bytes32(0), 0);
    }

    function testSetDefaultTradingFeeSuccess(
        address loanToken,
        uint256 postMaturityFee,
        uint256 oneDayFee,
        uint256 sevenDaysFee,
        uint256 thirtyDaysFee,
        uint256 ninetyDaysFee,
        uint256 oneEightyDaysFee,
        uint256 threeSixtyDaysFee
    ) public {
        postMaturityFee = bound(postMaturityFee, 0, midnight.maxTradingFee(0)) / 1e12 * 1e12;
        oneDayFee = bound(oneDayFee, postMaturityFee, midnight.maxTradingFee(1)) / 1e12 * 1e12;
        sevenDaysFee = bound(sevenDaysFee, oneDayFee, midnight.maxTradingFee(2)) / 1e12 * 1e12;
        thirtyDaysFee = bound(thirtyDaysFee, sevenDaysFee, midnight.maxTradingFee(3)) / 1e12 * 1e12;
        ninetyDaysFee = bound(ninetyDaysFee, thirtyDaysFee, midnight.maxTradingFee(4)) / 1e12 * 1e12;
        oneEightyDaysFee = bound(oneEightyDaysFee, ninetyDaysFee, midnight.maxTradingFee(5)) / 1e12 * 1e12;
        threeSixtyDaysFee = bound(threeSixtyDaysFee, oneEightyDaysFee, midnight.maxTradingFee(6)) / 1e12 * 1e12;

        midnight.setDefaultTradingFee(loanToken, 0, postMaturityFee);
        midnight.setDefaultTradingFee(loanToken, 1, oneDayFee);
        midnight.setDefaultTradingFee(loanToken, 2, sevenDaysFee);
        midnight.setDefaultTradingFee(loanToken, 3, thirtyDaysFee);
        midnight.setDefaultTradingFee(loanToken, 4, ninetyDaysFee);
        midnight.setDefaultTradingFee(loanToken, 5, oneEightyDaysFee);
        midnight.setDefaultTradingFee(loanToken, 6, threeSixtyDaysFee);

        // touch obligation with this loan token
        Collateral[] memory collaterals = new Collateral[](1);
        collaterals[0] = Collateral({
            token: address(collateralToken1), lltv: 0.75e18, maxLif: maxLif(0.75e18, 0.25e18), oracle: address(oracle1)
        });
        Obligation memory obligation = Obligation({
            loanToken: loanToken,
            maturity: block.timestamp + 1 days,
            collaterals: collaterals,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        bytes32 id = toId(obligation);
        midnight.touchObligation(obligation);

        assertEq(midnight.tradingFee(id, 0), postMaturityFee, "0 days default fee");
        assertEq(midnight.tradingFee(id, 1 days), oneDayFee, "1 day default fee");
        assertEq(midnight.tradingFee(id, 7 days), sevenDaysFee, "7 days default fee");
        assertEq(midnight.tradingFee(id, 30 days), thirtyDaysFee, "30 days default fee");
        assertEq(midnight.tradingFee(id, 90 days), ninetyDaysFee, "90 days default fee");
        assertEq(midnight.tradingFee(id, 180 days), oneEightyDaysFee, "180 days default fee");
        assertEq(midnight.tradingFee(id, 360 days), threeSixtyDaysFee, "360 days default fee");
        assertEq(midnight.tradingFee(id, 365 days), threeSixtyDaysFee, "365 days default fee");
        assertEq(midnight.tradingFee(id, 1000 days), threeSixtyDaysFee, "1000 days default fee");
    }

    function testSetDefaultTradingFeeOnlyFeeSetter(address rdm, address loanToken) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("only fee setter");
        midnight.setDefaultTradingFee(loanToken, 0, 0);
    }

    function testSetDefaultTradingFeeValidation(address loanToken, uint256 feeTooHigh, uint256 index) public {
        index = bound(index, 0, 6);
        feeTooHigh = bound(feeTooHigh, midnight.maxTradingFee(index) + 1, 1e18);
        vm.expectRevert("value too high");
        midnight.setDefaultTradingFee(loanToken, index, feeTooHigh);
    }

    function testLinearInterpolation(
        uint256 fee0,
        uint256 fee1,
        uint256 fee2,
        uint256 fee3,
        uint256 fee4,
        uint256 fee5,
        uint256 fee6
    ) public {
        fee0 = bound(fee0, 0, midnight.maxTradingFee(0)) / 1e12 * 1e12;
        fee1 = bound(fee1, 0, midnight.maxTradingFee(1)) / 1e12 * 1e12;
        fee2 = bound(fee2, 0, midnight.maxTradingFee(2)) / 1e12 * 1e12;
        fee3 = bound(fee3, 0, midnight.maxTradingFee(3)) / 1e12 * 1e12;
        fee4 = bound(fee4, 0, midnight.maxTradingFee(4)) / 1e12 * 1e12;
        fee5 = bound(fee5, 0, midnight.maxTradingFee(5)) / 1e12 * 1e12;
        fee6 = bound(fee6, 0, midnight.maxTradingFee(6)) / 1e12 * 1e12;

        Collateral[] memory cols = new Collateral[](1);
        cols[0] = Collateral({
            token: address(collateralToken1), lltv: 0.75e18, maxLif: maxLif(0.75e18, 0.25e18), oracle: address(oracle1)
        });
        Obligation memory obligation = Obligation({
            loanToken: address(0),
            maturity: block.timestamp + 1 days,
            collaterals: cols,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        bytes32 id = toId(obligation);
        midnight.touchObligation(obligation);

        midnight.setObligationTradingFee(id, 0, fee0);
        midnight.setObligationTradingFee(id, 1, fee1);
        midnight.setObligationTradingFee(id, 2, fee2);
        midnight.setObligationTradingFee(id, 3, fee3);
        midnight.setObligationTradingFee(id, 4, fee4);
        midnight.setObligationTradingFee(id, 5, fee5);
        midnight.setObligationTradingFee(id, 6, fee6);

        // Test exact breakpoints
        assertEq(midnight.tradingFee(id, 0), fee0, "0 days");
        assertEq(midnight.tradingFee(id, 1 days), fee1, "1 day");
        assertEq(midnight.tradingFee(id, 7 days), fee2, "7 days");
        assertEq(midnight.tradingFee(id, 30 days), fee3, "30 days");
        assertEq(midnight.tradingFee(id, 90 days), fee4, "90 days");
        assertEq(midnight.tradingFee(id, 180 days), fee5, "180 days");
        assertEq(midnight.tradingFee(id, 360 days), fee6, "360 days");

        // Test interpolation midpoint (0.5 days is between index 0 and 1)
        uint256 expectedMidpoint = (fee0 * (1 days - 0.5 days) + fee1 * (0.5 days)) / 1 days;
        assertEq(midnight.tradingFee(id, 0.5 days), expectedMidpoint, "Midpoint 0-1d");

        // Test interpolation midpoint (4 days is between index 1 and 2)
        uint256 expectedMid4d = (fee1 * (7 days - 4 days) + fee2 * (4 days - 1 days)) / (7 days - 1 days);
        assertEq(midnight.tradingFee(id, 4 days), expectedMid4d, "Midpoint 1-7d");

        // Test interpolation midpoint (270 days is between index 5 [180d] and index 6 [360d])
        uint256 expectedMid270d = (fee5 * (360 days - 270 days) + fee6 * (270 days - 180 days)) / (360 days - 180 days);
        assertEq(midnight.tradingFee(id, 270 days), expectedMid270d, "Midpoint 180-360d");

        // Test beyond 360 days
        assertEq(midnight.tradingFee(id, 365 days), fee6, "365 days");
        assertEq(midnight.tradingFee(id, 1000 days), fee6, "1000 days");
    }
}
