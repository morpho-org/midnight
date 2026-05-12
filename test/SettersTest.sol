// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {
    MAX_CONTINUOUS_FEE,
    MAX_TRADING_FEE_0_DAYS,
    MAX_TRADING_FEE_1_DAY,
    MAX_TRADING_FEE_7_DAYS,
    MAX_TRADING_FEE_30_DAYS,
    MAX_TRADING_FEE_90_DAYS,
    MAX_TRADING_FEE_180_DAYS,
    MAX_TRADING_FEE_360_DAYS
} from "../src/libraries/ConstantsLib.sol";
import {BaseTest} from "./BaseTest.sol";
import {IMidnight, Obligation, CollateralParams} from "../src/interfaces/IMidnight.sol";

contract SettersTest is BaseTest {
    function testMaxTradingFeeConstants() public pure {
        assertEq(maxTradingFee(0), MAX_TRADING_FEE_0_DAYS, "0 days max trading fee");
        assertEq(maxTradingFee(1), MAX_TRADING_FEE_1_DAY, "1 day max trading fee");
        assertEq(maxTradingFee(2), MAX_TRADING_FEE_7_DAYS, "7 days max trading fee");
        assertEq(maxTradingFee(3), MAX_TRADING_FEE_30_DAYS, "30 days max trading fee");
        assertEq(maxTradingFee(4), MAX_TRADING_FEE_90_DAYS, "90 days max trading fee");
        assertEq(maxTradingFee(5), MAX_TRADING_FEE_180_DAYS, "180 days max trading fee");
        assertEq(maxTradingFee(6), MAX_TRADING_FEE_360_DAYS, "360 days max trading fee");
    }

    function testInitialRoleSetter() public view {
        assertEq(midnight.roleSetter(), address(this), "deployer should be initial role setter");
    }

    function testSetRoleSetterSuccess(address rdm) public {
        midnight.setRoleSetter(rdm);
        assertEq(midnight.roleSetter(), rdm, "role setter should be transferred");
    }

    function testSetRoleSetterOnlyRoleSetter(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert(IMidnight.OnlyRoleSetter.selector);
        midnight.setRoleSetter(makeAddr("newRoleSetter"));
    }

    function testSetFeeSetterSuccess(address feeSetter) public {
        midnight.setFeeSetter(feeSetter);
        assertEq(midnight.feeSetter(), feeSetter);
    }

    function testSetFeeSetterOnlyRoleSetter(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert(IMidnight.OnlyRoleSetter.selector);
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
        postMaturityFee = bound(postMaturityFee, 0, maxTradingFee(0)) / 1e12 * 1e12;
        oneDayFee = bound(oneDayFee, 0, maxTradingFee(1)) / 1e12 * 1e12;
        sevenDaysFee = bound(sevenDaysFee, 0, maxTradingFee(2)) / 1e12 * 1e12;
        thirtyDaysFee = bound(thirtyDaysFee, 0, maxTradingFee(3)) / 1e12 * 1e12;
        ninetyDaysFee = bound(ninetyDaysFee, 0, maxTradingFee(4)) / 1e12 * 1e12;
        oneEightyDaysFee = bound(oneEightyDaysFee, 0, maxTradingFee(5)) / 1e12 * 1e12;
        threeSixtyDaysFee = bound(threeSixtyDaysFee, 0, maxTradingFee(6)) / 1e12 * 1e12;

        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        Obligation memory obligation = Obligation({
            loanToken: loanToken,
            maturity: block.timestamp + 1 days,
            collateralParams: collateralParams,
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
        vm.expectRevert(IMidnight.InvalidFeeIndex.selector);
        midnight.setObligationTradingFee(id, 7, 0);
    }

    function testSetDefaultTradingFeeInvalidIndex(address loanToken) public {
        vm.expectRevert(IMidnight.InvalidFeeIndex.selector);
        midnight.setDefaultTradingFee(loanToken, 7, 0);
    }

    function testSetObligationTradingFeeValueTooHigh(bytes32 id, uint256 feeTooHigh, uint256 index) public {
        index = bound(index, 0, 6);
        feeTooHigh = bound(feeTooHigh, maxTradingFee(index) + 1, 1e18);
        vm.expectRevert(IMidnight.TradingFeeTooHigh.selector);
        midnight.setObligationTradingFee(id, index, feeTooHigh);
    }

    function testSetTradingFeeNotMultipleOfFeeStep(bytes32 id, uint256 index, uint256 fee) public {
        index = bound(index, 0, 6);
        fee = bound(fee, 1, maxTradingFee(index));
        vm.assume(fee % 1e12 != 0);
        vm.expectRevert(IMidnight.FeeNotMultipleOfFeeStep.selector);
        midnight.setObligationTradingFee(id, index, fee);
    }

    function testSetDefaultTradingFeeNotMultipleOfFeeStep(address loanToken, uint256 index, uint256 fee) public {
        index = bound(index, 0, 6);
        fee = bound(fee, 1, maxTradingFee(index));
        vm.assume(fee % 1e12 != 0);
        vm.expectRevert(IMidnight.FeeNotMultipleOfFeeStep.selector);
        midnight.setDefaultTradingFee(loanToken, index, fee);
    }

    function testSetObligationTradingFeeObligationNotCreated(bytes32 id) public {
        vm.expectRevert(IMidnight.ObligationNotCreated.selector);
        midnight.setObligationTradingFee(id, 0, 0);
    }

    function testSetObligationContinuousFeeObligationNotCreated(bytes32 id, uint256 fee) public {
        fee = bound(fee, 0, MAX_CONTINUOUS_FEE);
        vm.expectRevert(IMidnight.ObligationNotCreated.selector);
        midnight.setObligationContinuousFee(id, fee);
    }

    function testSetTradingFeeOnlyFeeSetter(address rdm, bytes32 id) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert(IMidnight.OnlyFeeSetter.selector);
        midnight.setObligationTradingFee(id, 0, 0);
    }

    function testSetFeeClaimerSuccess(address feeClaimer) public {
        midnight.setFeeClaimer(feeClaimer);
        assertEq(midnight.feeClaimer(), feeClaimer, "fee claimer set");
    }

    function testSetFeeClaimerOnlyRoleSetter(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert(IMidnight.OnlyRoleSetter.selector);
        midnight.setFeeClaimer(makeAddr("newRecipient"));
    }

    // Default trading fee tests

    function testTradingFeeRevertsWhenNotCreated() public {
        vm.expectRevert(IMidnight.ObligationNotCreated.selector);
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
        postMaturityFee = bound(postMaturityFee, 0, maxTradingFee(0)) / 1e12 * 1e12;
        oneDayFee = bound(oneDayFee, postMaturityFee, maxTradingFee(1)) / 1e12 * 1e12;
        sevenDaysFee = bound(sevenDaysFee, oneDayFee, maxTradingFee(2)) / 1e12 * 1e12;
        thirtyDaysFee = bound(thirtyDaysFee, sevenDaysFee, maxTradingFee(3)) / 1e12 * 1e12;
        ninetyDaysFee = bound(ninetyDaysFee, thirtyDaysFee, maxTradingFee(4)) / 1e12 * 1e12;
        oneEightyDaysFee = bound(oneEightyDaysFee, ninetyDaysFee, maxTradingFee(5)) / 1e12 * 1e12;
        threeSixtyDaysFee = bound(threeSixtyDaysFee, oneEightyDaysFee, maxTradingFee(6)) / 1e12 * 1e12;

        midnight.setDefaultTradingFee(loanToken, 0, postMaturityFee);
        midnight.setDefaultTradingFee(loanToken, 1, oneDayFee);
        midnight.setDefaultTradingFee(loanToken, 2, sevenDaysFee);
        midnight.setDefaultTradingFee(loanToken, 3, thirtyDaysFee);
        midnight.setDefaultTradingFee(loanToken, 4, ninetyDaysFee);
        midnight.setDefaultTradingFee(loanToken, 5, oneEightyDaysFee);
        midnight.setDefaultTradingFee(loanToken, 6, threeSixtyDaysFee);

        // touch obligation with this loan token
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        Obligation memory obligation = Obligation({
            loanToken: loanToken,
            maturity: block.timestamp + 1 days,
            collateralParams: collateralParams,
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
        vm.expectRevert(IMidnight.OnlyFeeSetter.selector);
        midnight.setDefaultTradingFee(loanToken, 0, 0);
    }

    function testSetDefaultTradingFeeValidation(address loanToken, uint256 feeTooHigh, uint256 index) public {
        index = bound(index, 0, 6);
        feeTooHigh = bound(feeTooHigh, maxTradingFee(index) + 1, 1e18);
        vm.expectRevert(IMidnight.TradingFeeTooHigh.selector);
        midnight.setDefaultTradingFee(loanToken, index, feeTooHigh);
    }

    function testTradingFeeLinearInterpolation(
        uint256 tradingFee0,
        uint256 tradingFee1,
        uint256 tradingFee2,
        uint256 tradingFee3,
        uint256 tradingFee4,
        uint256 tradingFee5,
        uint256 tradingFee6
    ) public {
        tradingFee0 = bound(tradingFee0, 0, maxTradingFee(0)) / 1e12 * 1e12;
        tradingFee1 = bound(tradingFee1, 0, maxTradingFee(1)) / 1e12 * 1e12;
        tradingFee2 = bound(tradingFee2, 0, maxTradingFee(2)) / 1e12 * 1e12;
        tradingFee3 = bound(tradingFee3, 0, maxTradingFee(3)) / 1e12 * 1e12;
        tradingFee4 = bound(tradingFee4, 0, maxTradingFee(4)) / 1e12 * 1e12;
        tradingFee5 = bound(tradingFee5, 0, maxTradingFee(5)) / 1e12 * 1e12;
        tradingFee6 = bound(tradingFee6, 0, maxTradingFee(6)) / 1e12 * 1e12;

        CollateralParams[] memory cols = new CollateralParams[](1);
        cols[0] = CollateralParams({
            token: address(collateralToken1), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        Obligation memory obligation = Obligation({
            loanToken: address(0),
            maturity: block.timestamp + 1 days,
            collateralParams: cols,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        bytes32 id = toId(obligation);
        midnight.touchObligation(obligation);

        midnight.setObligationTradingFee(id, 0, tradingFee0);
        midnight.setObligationTradingFee(id, 1, tradingFee1);
        midnight.setObligationTradingFee(id, 2, tradingFee2);
        midnight.setObligationTradingFee(id, 3, tradingFee3);
        midnight.setObligationTradingFee(id, 4, tradingFee4);
        midnight.setObligationTradingFee(id, 5, tradingFee5);
        midnight.setObligationTradingFee(id, 6, tradingFee6);

        // Test exact breakpoints
        assertEq(midnight.tradingFee(id, 0), tradingFee0, "0 days");
        assertEq(midnight.tradingFee(id, 1 days), tradingFee1, "1 day");
        assertEq(midnight.tradingFee(id, 7 days), tradingFee2, "7 days");
        assertEq(midnight.tradingFee(id, 30 days), tradingFee3, "30 days");
        assertEq(midnight.tradingFee(id, 90 days), tradingFee4, "90 days");
        assertEq(midnight.tradingFee(id, 180 days), tradingFee5, "180 days");
        assertEq(midnight.tradingFee(id, 360 days), tradingFee6, "360 days");

        // Test interpolation midpoint (0.5 days is between index 0 and 1)
        uint256 expectedMidpoint = (tradingFee0 * (1 days - 0.5 days) + tradingFee1 * (0.5 days)) / 1 days;
        assertEq(midnight.tradingFee(id, 0.5 days), expectedMidpoint, "Midpoint 0-1d");

        // Test interpolation midpoint (4 days is between index 1 and 2)
        uint256 expectedMid4d = (tradingFee1 * (7 days - 4 days) + tradingFee2 * (4 days - 1 days)) / (7 days - 1 days);
        assertEq(midnight.tradingFee(id, 4 days), expectedMid4d, "Midpoint 1-7d");

        // Test interpolation midpoint (270 days is between index 5 [180d] and index 6 [360d])
        uint256 expectedMid270d =
            (tradingFee5 * (360 days - 270 days) + tradingFee6 * (270 days - 180 days)) / (360 days - 180 days);
        assertEq(midnight.tradingFee(id, 270 days), expectedMid270d, "Midpoint 180-360d");

        // Test beyond 360 days
        assertEq(midnight.tradingFee(id, 365 days), tradingFee6, "365 days");
        assertEq(midnight.tradingFee(id, 1000 days), tradingFee6, "1000 days");
    }

    function testSetContinuousFeeOnlyFeeSetter(address rdm) public {
        vm.assume(rdm != address(this));

        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        Obligation memory obligation = Obligation({
            loanToken: address(loanToken),
            maturity: block.timestamp + 100 days,
            collateralParams: collateralParams,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        midnight.touchObligation(obligation);
        bytes32 id = toId(obligation);

        vm.prank(rdm);
        vm.expectRevert(IMidnight.OnlyFeeSetter.selector);
        midnight.setObligationContinuousFee(id, 100);

        vm.prank(rdm);
        vm.expectRevert(IMidnight.OnlyFeeSetter.selector);
        midnight.setDefaultContinuousFee(address(loanToken), 100);
    }

    function testSetContinuousFeeTooHigh(uint256 fee) public {
        fee = bound(fee, MAX_CONTINUOUS_FEE + 1, type(uint256).max);

        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        Obligation memory obligation = Obligation({
            loanToken: address(loanToken),
            maturity: block.timestamp + 100 days,
            collateralParams: collateralParams,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        midnight.touchObligation(obligation);
        bytes32 id = toId(obligation);

        vm.expectRevert(IMidnight.ContinuousFeeTooHigh.selector);
        midnight.setObligationContinuousFee(id, fee);

        vm.expectRevert(IMidnight.ContinuousFeeTooHigh.selector);
        midnight.setDefaultContinuousFee(address(loanToken), fee);
    }

    function testSetContinuousFeeSuccess(uint256 fee, uint256 fee2) public {
        fee = bound(fee, 0, MAX_CONTINUOUS_FEE);
        fee2 = bound(fee2, 0, MAX_CONTINUOUS_FEE);
        vm.assume(fee != fee2);

        midnight.setDefaultContinuousFee(address(loanToken), fee);
        assertEq(midnight.defaultContinuousFee(address(loanToken)), fee, "default fee updated");

        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        Obligation memory obligation = Obligation({
            loanToken: address(loanToken),
            maturity: block.timestamp + 100 days,
            collateralParams: collateralParams,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        midnight.touchObligation(obligation);
        bytes32 id = toId(obligation);

        assertEq(midnight.continuousFee(id), fee, "obligation inherits default fee");
        midnight.setObligationContinuousFee(id, fee2);
        assertEq(midnight.continuousFee(id), fee2, "obligation fee updated");
    }
}
