// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {Obligation, Collateral} from "../src/interfaces/IMorphoV2.sol";

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

    function testSetTradingFeeSuccess(
        address loanToken,
        uint256 postMaturityFee,
        uint256 oneDayFee,
        uint256 sevenDaysFee,
        uint256 thirtyDaysFee,
        uint256 ninetyDaysFee,
        uint256 oneEightyDaysFee
    ) public {
        postMaturityFee = bound(postMaturityFee, 0, morphoV2.maxTradingFee(0)) / 1e12 * 1e12;
        oneDayFee = bound(oneDayFee, 0, morphoV2.maxTradingFee(1)) / 1e12 * 1e12;
        sevenDaysFee = bound(sevenDaysFee, 0, morphoV2.maxTradingFee(2)) / 1e12 * 1e12;
        thirtyDaysFee = bound(thirtyDaysFee, 0, morphoV2.maxTradingFee(3)) / 1e12 * 1e12;
        ninetyDaysFee = bound(ninetyDaysFee, 0, morphoV2.maxTradingFee(4)) / 1e12 * 1e12;
        oneEightyDaysFee = bound(oneEightyDaysFee, 0, morphoV2.maxTradingFee(5)) / 1e12 * 1e12;

        Obligation memory obligation = Obligation({
            loanToken: loanToken, maturity: block.timestamp + 1 days, collaterals: new Collateral[](0), rcfThreshold: 0
        });
        bytes20 id = toId(obligation);
        morphoV2.touchObligation(obligation);

        morphoV2.setObligationTradingFee(id, 0, postMaturityFee);
        morphoV2.setObligationTradingFee(id, 1, oneDayFee);
        morphoV2.setObligationTradingFee(id, 2, sevenDaysFee);
        morphoV2.setObligationTradingFee(id, 3, thirtyDaysFee);
        morphoV2.setObligationTradingFee(id, 4, ninetyDaysFee);
        morphoV2.setObligationTradingFee(id, 5, oneEightyDaysFee);

        assertEq(morphoV2.tradingFee(id, 0), postMaturityFee, "post maturity trading fee");
        assertEq(morphoV2.tradingFee(id, 1 days), oneDayFee, "one day trading fee");
        assertEq(morphoV2.tradingFee(id, 7 days), sevenDaysFee, "seven days trading fee");
        assertEq(morphoV2.tradingFee(id, 30 days), thirtyDaysFee, "thirty days trading fee");
        assertEq(morphoV2.tradingFee(id, 90 days), ninetyDaysFee, "ninety days trading fee");
        assertEq(morphoV2.tradingFee(id, 180 days), oneEightyDaysFee, "one eighty days trading fee");
        assertEq(morphoV2.tradingFee(id, 365 days), oneEightyDaysFee, "three sixty five days trading fee");
        assertEq(morphoV2.tradingFee(id, 1000 days), oneEightyDaysFee, "one thousand days trading fee");
    }

    function testSetTradingFeeOnlyFeeSetter(address rdm, bytes20 id) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setObligationTradingFee(id, 0, 0);
    }

    function testSetTradingFeeRecipientSuccess(address feeRecipient) public {
        morphoV2.setTradingFeeRecipient(feeRecipient);
        assertEq(morphoV2.tradingFeeRecipient(), feeRecipient, "fee recipient set");
    }

    function testSetTradingFeeRecipientOnlyOwner(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only owner");
        morphoV2.setTradingFeeRecipient(makeAddr("newRecipient"));
    }

    // Default trading fee tests

    function testUnsetDefaultFeeReturnsZero() public view {
        assertEq(morphoV2.tradingFee(bytes20(0), 0), 0, "unset default fee should be 0");
        assertEq(morphoV2.tradingFee(bytes20(0), 1 days), 0, "unset default fee should be 0");
        assertEq(morphoV2.tradingFee(bytes20(0), 7 days), 0, "unset default fee should be 0");
        assertEq(morphoV2.tradingFee(bytes20(0), 30 days), 0, "unset default fee should be 0");
        assertEq(morphoV2.tradingFee(bytes20(0), 90 days), 0, "unset default fee should be 0");
    }

    function testSetDefaultTradingFeeSuccess(
        address loanToken,
        uint256 postMaturityFee,
        uint256 oneDayFee,
        uint256 sevenDaysFee,
        uint256 thirtyDaysFee,
        uint256 ninetyDaysFee,
        uint256 oneEightyDaysFee
    ) public {
        postMaturityFee = bound(postMaturityFee, 0, morphoV2.maxTradingFee(0)) / 1e12 * 1e12;
        oneDayFee = bound(oneDayFee, postMaturityFee, morphoV2.maxTradingFee(1)) / 1e12 * 1e12;
        sevenDaysFee = bound(sevenDaysFee, oneDayFee, morphoV2.maxTradingFee(2)) / 1e12 * 1e12;
        thirtyDaysFee = bound(thirtyDaysFee, sevenDaysFee, morphoV2.maxTradingFee(3)) / 1e12 * 1e12;
        ninetyDaysFee = bound(ninetyDaysFee, thirtyDaysFee, morphoV2.maxTradingFee(4)) / 1e12 * 1e12;
        oneEightyDaysFee = bound(oneEightyDaysFee, ninetyDaysFee, morphoV2.maxTradingFee(5)) / 1e12 * 1e12;

        morphoV2.setDefaultTradingFee(loanToken, 0, postMaturityFee);
        morphoV2.setDefaultTradingFee(loanToken, 1, oneDayFee);
        morphoV2.setDefaultTradingFee(loanToken, 2, sevenDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 3, thirtyDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 4, ninetyDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 5, oneEightyDaysFee);

        // touch obligation with this loan token
        Obligation memory obligation = Obligation({
            loanToken: loanToken, maturity: block.timestamp + 1 days, collaterals: new Collateral[](0), rcfThreshold: 0
        });
        bytes20 id = toId(obligation);
        morphoV2.touchObligation(obligation);

        assertEq(morphoV2.tradingFee(id, 0), postMaturityFee, "0 days default fee");
        assertEq(morphoV2.tradingFee(id, 1 days), oneDayFee, "1 day default fee");
        assertEq(morphoV2.tradingFee(id, 7 days), sevenDaysFee, "7 days default fee");
        assertEq(morphoV2.tradingFee(id, 30 days), thirtyDaysFee, "30 days default fee");
        assertEq(morphoV2.tradingFee(id, 90 days), ninetyDaysFee, "90 days default fee");
        assertEq(morphoV2.tradingFee(id, 180 days), oneEightyDaysFee, "180 days default fee");
        assertEq(morphoV2.tradingFee(id, 365 days), oneEightyDaysFee, "365 days default fee");
        assertEq(morphoV2.tradingFee(id, 1000 days), oneEightyDaysFee, "1000 days default fee");
    }

    function testSetDefaultTradingFeeOnlyFeeSetter(address rdm, address loanToken) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert("Only feeSetter");
        morphoV2.setDefaultTradingFee(loanToken, 0, 0);
    }

    function testSetDefaultTradingFeeValidation(address loanToken, uint256 feeTooHigh, uint256 index) public {
        index = bound(index, 0, 5);
        feeTooHigh = bound(feeTooHigh, morphoV2.maxTradingFee(index) + 1, 1e18);
        vm.expectRevert("value too high");
        morphoV2.setDefaultTradingFee(loanToken, index, feeTooHigh);
    }

    function testLinearInterpolation(uint256 fee0, uint256 fee1, uint256 fee2, uint256 fee3, uint256 fee4, uint256 fee5)
        public
    {
        fee0 = bound(fee0, 0, morphoV2.maxTradingFee(0)) / 1e12 * 1e12;
        fee1 = bound(fee1, 0, morphoV2.maxTradingFee(1)) / 1e12 * 1e12;
        fee2 = bound(fee2, 0, morphoV2.maxTradingFee(2)) / 1e12 * 1e12;
        fee3 = bound(fee3, 0, morphoV2.maxTradingFee(3)) / 1e12 * 1e12;
        fee4 = bound(fee4, 0, morphoV2.maxTradingFee(4)) / 1e12 * 1e12;
        fee5 = bound(fee5, 0, morphoV2.maxTradingFee(5)) / 1e12 * 1e12;

        Obligation memory obligation = Obligation({
            loanToken: address(0), maturity: block.timestamp + 1 days, collaterals: new Collateral[](0), rcfThreshold: 0
        });
        bytes20 id = toId(obligation);
        morphoV2.touchObligation(obligation);

        morphoV2.setObligationTradingFee(id, 0, fee0);
        morphoV2.setObligationTradingFee(id, 1, fee1);
        morphoV2.setObligationTradingFee(id, 2, fee2);
        morphoV2.setObligationTradingFee(id, 3, fee3);
        morphoV2.setObligationTradingFee(id, 4, fee4);
        morphoV2.setObligationTradingFee(id, 5, fee5);

        // Test exact breakpoints
        assertEq(morphoV2.tradingFee(id, 0), fee0, "0 days");
        assertEq(morphoV2.tradingFee(id, 1 days), fee1, "1 day");
        assertEq(morphoV2.tradingFee(id, 7 days), fee2, "7 days");
        assertEq(morphoV2.tradingFee(id, 30 days), fee3, "30 days");
        assertEq(morphoV2.tradingFee(id, 90 days), fee4, "90 days");
        assertEq(morphoV2.tradingFee(id, 180 days), fee5, "180 days");

        // Test interpolation midpoint (0.5 days is between index 0 and 1)
        uint256 expectedMidpoint = (fee0 * (1 days - 0.5 days) + fee1 * (0.5 days)) / 1 days;
        assertEq(morphoV2.tradingFee(id, 0.5 days), expectedMidpoint, "Midpoint 0-1d");

        // Test interpolation midpoint (4 days is between index 1 and 2)
        uint256 expectedMid4d = (fee1 * (7 days - 4 days) + fee2 * (4 days - 1 days)) / (7 days - 1 days);
        assertEq(morphoV2.tradingFee(id, 4 days), expectedMid4d, "Midpoint 1-7d");

        // Test beyond 180 days
        assertEq(morphoV2.tradingFee(id, 365 days), fee5, "365 days");
        assertEq(morphoV2.tradingFee(id, 1000 days), fee5, "1000 days");
    }
}
