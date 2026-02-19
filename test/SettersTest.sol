// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {MAX_FEE} from "../src/libraries/ConstantsLib.sol";
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
        uint256 zeroSecondsFee,
        uint256 oneDayFee,
        uint256 sevenDaysFee,
        uint256 thirtyDaysFee,
        uint256 ninetyDaysFee,
        uint256 oneEightyDaysFee
    ) public {
        zeroSecondsFee = bound(zeroSecondsFee, 0, MAX_FEE) / 1e12 * 1e12;
        oneDayFee = bound(oneDayFee, zeroSecondsFee, MAX_FEE) / 1e12 * 1e12;
        sevenDaysFee = bound(sevenDaysFee, oneDayFee, MAX_FEE) / 1e12 * 1e12;
        thirtyDaysFee = bound(thirtyDaysFee, sevenDaysFee, MAX_FEE) / 1e12 * 1e12;
        ninetyDaysFee = bound(ninetyDaysFee, thirtyDaysFee, MAX_FEE) / 1e12 * 1e12;
        oneEightyDaysFee = bound(oneEightyDaysFee, ninetyDaysFee, MAX_FEE) / 1e12 * 1e12;

        // first set the default trading fee for this loan token
        morphoV2.setDefaultTradingFee(loanToken, 0, zeroSecondsFee);
        morphoV2.setDefaultTradingFee(loanToken, 1, oneDayFee);
        morphoV2.setDefaultTradingFee(loanToken, 2, sevenDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 3, thirtyDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 4, ninetyDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 5, oneEightyDaysFee);

        // touch obligation with this loan token
        Obligation memory obligation = Obligation({
            loanToken: loanToken,
            maturity: block.timestamp + 1 days,
            collaterals: new Collateral[](0),
            minCollatValue: 0
        });
        bytes20 id = toId(obligation);
        morphoV2.touchObligation(obligation);

        morphoV2.setObligationTradingFee(id, 0, zeroSecondsFee);
        morphoV2.setObligationTradingFee(id, 1, oneDayFee);
        morphoV2.setObligationTradingFee(id, 2, sevenDaysFee);
        morphoV2.setObligationTradingFee(id, 3, thirtyDaysFee);
        morphoV2.setObligationTradingFee(id, 4, ninetyDaysFee);
        morphoV2.setObligationTradingFee(id, 5, oneEightyDaysFee);

        assertEq(morphoV2.tradingFee(id, 0), zeroSecondsFee, "zero days trading fee");
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
        postMaturityFee = bound(postMaturityFee, 0, MAX_FEE) / 1e12 * 1e12;
        oneDayFee = bound(oneDayFee, postMaturityFee, MAX_FEE) / 1e12 * 1e12;
        sevenDaysFee = bound(sevenDaysFee, oneDayFee, MAX_FEE) / 1e12 * 1e12;
        thirtyDaysFee = bound(thirtyDaysFee, sevenDaysFee, MAX_FEE) / 1e12 * 1e12;
        ninetyDaysFee = bound(ninetyDaysFee, thirtyDaysFee, MAX_FEE) / 1e12 * 1e12;
        oneEightyDaysFee = bound(oneEightyDaysFee, ninetyDaysFee, MAX_FEE) / 1e12 * 1e12;

        morphoV2.setDefaultTradingFee(loanToken, 0, postMaturityFee);
        morphoV2.setDefaultTradingFee(loanToken, 1, oneDayFee);
        morphoV2.setDefaultTradingFee(loanToken, 2, sevenDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 3, thirtyDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 4, ninetyDaysFee);
        morphoV2.setDefaultTradingFee(loanToken, 5, oneEightyDaysFee);

        // touch obligation with this loan token
        Obligation memory obligation = Obligation({
            loanToken: loanToken,
            maturity: block.timestamp + 1 days,
            collaterals: new Collateral[](0),
            minCollatValue: 0
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

    function testSetDefaultTradingFeeValidation(address loanToken, uint256 feeTooHigh) public {
        feeTooHigh = bound(feeTooHigh, MAX_FEE + 1, 2 * MAX_FEE);
        vm.expectRevert("Trading fee too high");
        morphoV2.setDefaultTradingFee(loanToken, 0, feeTooHigh);
    }

    function testDefaultTradingFeeTTMBuckets() public {
        address loanToken = makeAddr("loanToken");

        morphoV2.setDefaultTradingFee(loanToken, 0, 0.001e18);
        morphoV2.setDefaultTradingFee(loanToken, 1, 0.002e18);
        morphoV2.setDefaultTradingFee(loanToken, 2, 0.003e18);
        morphoV2.setDefaultTradingFee(loanToken, 3, 0.005e18);
        morphoV2.setDefaultTradingFee(loanToken, 4, 0.007e18);
        morphoV2.setDefaultTradingFee(loanToken, 5, 0.01e18);

        // touch obligation with this loan token
        Obligation memory obligation = Obligation({
            loanToken: loanToken,
            maturity: block.timestamp + 1 days,
            collaterals: new Collateral[](0),
            minCollatValue: 0
        });
        bytes20 id = toId(obligation);
        morphoV2.touchObligation(obligation);

        // Test breakpoint 0: 0 days (post maturity)
        assertEq(morphoV2.tradingFee(id, 0), 0.001e18, "0 days");

        // Test breakpoint 1: 1 day
        assertEq(morphoV2.tradingFee(id, 1 days), 0.002e18, "1 day");

        // Test breakpoint 2: 7 days
        assertEq(morphoV2.tradingFee(id, 7 days), 0.003e18, "7 days");

        // Test breakpoint 3: 30 days
        assertEq(morphoV2.tradingFee(id, 30 days), 0.005e18, "30 days");

        // Test breakpoint 4: 90 days
        assertEq(morphoV2.tradingFee(id, 90 days), 0.007e18, "90 days");

        // Test breakpoint 5: 180 days
        assertEq(morphoV2.tradingFee(id, 180 days), 0.01e18, "180 days");

        // Test beyond 180 days (should use breakpoint 5 fee)
        assertEq(morphoV2.tradingFee(id, 365 days), 0.01e18, "365 days");
        assertEq(morphoV2.tradingFee(id, 1000 days), 0.01e18, "1000 days");
    }

    function testLinearInterpolation() public {
        address loanToken = makeAddr("loanToken");

        // Fees scaled to fit within 1% cap (values /10 from original)
        morphoV2.setDefaultTradingFee(loanToken, 0, 0.001e18); // 0d: 0.1%
        morphoV2.setDefaultTradingFee(loanToken, 1, 0.002e18); // 1d: 0.2%
        morphoV2.setDefaultTradingFee(loanToken, 2, 0.004e18); // 7d: 0.4%
        morphoV2.setDefaultTradingFee(loanToken, 3, 0.006e18); // 30d: 0.6%
        morphoV2.setDefaultTradingFee(loanToken, 4, 0.008e18); // 90d: 0.8%
        morphoV2.setDefaultTradingFee(loanToken, 5, 0.01e18); // 180d: 1%

        // touch obligation with this loan token
        Obligation memory obligation = Obligation({
            loanToken: loanToken,
            maturity: block.timestamp + 1 days,
            collaterals: new Collateral[](0),
            minCollatValue: 0
        });
        bytes20 id = toId(obligation);
        morphoV2.touchObligation(obligation);

        // Test exact breakpoints
        assertEq(morphoV2.tradingFee(id, 0), 0.001e18, "0 days");
        assertEq(morphoV2.tradingFee(id, 1 days), 0.002e18, "1 day");
        assertEq(morphoV2.tradingFee(id, 7 days), 0.004e18, "7 days");
        assertEq(morphoV2.tradingFee(id, 30 days), 0.006e18, "30 days");
        assertEq(morphoV2.tradingFee(id, 90 days), 0.008e18, "90 days");
        assertEq(morphoV2.tradingFee(id, 180 days), 0.01e18, "180 days");

        // Test interpolation midpoints
        assertEq(morphoV2.tradingFee(id, 0.5 days), 0.0015e18, "Midpoint 0-1d");
        assertEq(morphoV2.tradingFee(id, 4 days), 0.003e18, "Midpoint 1-7d");

        // Test beyond 180 days
        assertEq(morphoV2.tradingFee(id, 365 days), 0.01e18, "365 days");
        assertEq(morphoV2.tradingFee(id, 1000 days), 0.01e18, "1000 days");
    }
}
