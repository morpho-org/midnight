// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {
    MAX_CONTINUOUS_FEE,
    MAX_SETTLEMENT_FEE_0_DAYS,
    MAX_SETTLEMENT_FEE_1_DAY,
    MAX_SETTLEMENT_FEE_7_DAYS,
    MAX_SETTLEMENT_FEE_30_DAYS,
    MAX_SETTLEMENT_FEE_90_DAYS,
    MAX_SETTLEMENT_FEE_180_DAYS,
    MAX_SETTLEMENT_FEE_360_DAYS
} from "../src/libraries/ConstantsLib.sol";
import {BaseTest} from "./BaseTest.sol";
import {IMidnight, Market, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {Midnight} from "../src/Midnight.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";

contract SettersTest is BaseTest {
    function testMaxSettlementFeeConstants() public pure {
        assertEq(maxSettlementFee(0), MAX_SETTLEMENT_FEE_0_DAYS, "0 days max settlement fee");
        assertEq(maxSettlementFee(1), MAX_SETTLEMENT_FEE_1_DAY, "1 day max settlement fee");
        assertEq(maxSettlementFee(2), MAX_SETTLEMENT_FEE_7_DAYS, "7 days max settlement fee");
        assertEq(maxSettlementFee(3), MAX_SETTLEMENT_FEE_30_DAYS, "30 days max settlement fee");
        assertEq(maxSettlementFee(4), MAX_SETTLEMENT_FEE_90_DAYS, "90 days max settlement fee");
        assertEq(maxSettlementFee(5), MAX_SETTLEMENT_FEE_180_DAYS, "180 days max settlement fee");
        assertEq(maxSettlementFee(6), MAX_SETTLEMENT_FEE_360_DAYS, "360 days max settlement fee");
    }

    function testInitialRoleSetter() public view {
        assertEq(midnight.roleSetter(), address(this), "deployer should be initial role setter");
    }

    function testConstructorEvent() public {
        vm.expectEmit();
        emit EventsLib.Constructor(address(this), block.chainid);

        new Midnight();
    }

    function testSetRoleSetterSuccess(address rdm) public {
        vm.expectEmit();
        emit EventsLib.SetRoleSetter(rdm);

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
        vm.expectEmit();
        emit EventsLib.SetFeeSetter(feeSetter);

        midnight.setFeeSetter(feeSetter);
        assertEq(midnight.feeSetter(), feeSetter);
    }

    function testSetTickSpacingSetterSuccess(address tickSpacingSetter) public {
        vm.expectEmit();
        emit EventsLib.SetTickSpacingSetter(tickSpacingSetter);

        midnight.setTickSpacingSetter(tickSpacingSetter);
        assertEq(midnight.tickSpacingSetter(), tickSpacingSetter);
    }

    function testSetFeeSetterOnlyRoleSetter(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert(IMidnight.OnlyRoleSetter.selector);
        midnight.setFeeSetter(makeAddr("newFeeSetter"));
    }

    function testSetSettlementFeeSuccess(
        address loanToken,
        uint256 postMaturityFee,
        uint256 oneDayFee,
        uint256 sevenDaysFee,
        uint256 thirtyDaysFee,
        uint256 ninetyDaysFee,
        uint256 oneEightyDaysFee,
        uint256 threeSixtyDaysFee
    ) public {
        postMaturityFee = bound(postMaturityFee, 0, maxSettlementFee(0)) / 1e12 * 1e12;
        oneDayFee = bound(oneDayFee, 0, maxSettlementFee(1)) / 1e12 * 1e12;
        sevenDaysFee = bound(sevenDaysFee, 0, maxSettlementFee(2)) / 1e12 * 1e12;
        thirtyDaysFee = bound(thirtyDaysFee, 0, maxSettlementFee(3)) / 1e12 * 1e12;
        ninetyDaysFee = bound(ninetyDaysFee, 0, maxSettlementFee(4)) / 1e12 * 1e12;
        oneEightyDaysFee = bound(oneEightyDaysFee, 0, maxSettlementFee(5)) / 1e12 * 1e12;
        threeSixtyDaysFee = bound(threeSixtyDaysFee, 0, maxSettlementFee(6)) / 1e12 * 1e12;

        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        Market memory market = Market({
            loanToken: loanToken,
            maturity: vm.getBlockTimestamp() + 1 days,
            collateralParams: collateralParams,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        bytes32 id = toId(market);
        midnight.touchMarket(market);

        vm.expectEmit();
        emit EventsLib.SetMarketSettlementFee(id, 0, postMaturityFee);
        midnight.setMarketSettlementFee(id, 0, postMaturityFee);

        vm.expectEmit();
        emit EventsLib.SetMarketSettlementFee(id, 1, oneDayFee);
        midnight.setMarketSettlementFee(id, 1, oneDayFee);

        vm.expectEmit();
        emit EventsLib.SetMarketSettlementFee(id, 2, sevenDaysFee);
        midnight.setMarketSettlementFee(id, 2, sevenDaysFee);

        vm.expectEmit();
        emit EventsLib.SetMarketSettlementFee(id, 3, thirtyDaysFee);
        midnight.setMarketSettlementFee(id, 3, thirtyDaysFee);

        vm.expectEmit();
        emit EventsLib.SetMarketSettlementFee(id, 4, ninetyDaysFee);
        midnight.setMarketSettlementFee(id, 4, ninetyDaysFee);

        vm.expectEmit();
        emit EventsLib.SetMarketSettlementFee(id, 5, oneEightyDaysFee);
        midnight.setMarketSettlementFee(id, 5, oneEightyDaysFee);

        vm.expectEmit();
        emit EventsLib.SetMarketSettlementFee(id, 6, threeSixtyDaysFee);
        midnight.setMarketSettlementFee(id, 6, threeSixtyDaysFee);

        assertEq(midnight.settlementFee(id, 0), postMaturityFee, "post maturity settlement fee");
        assertEq(midnight.settlementFee(id, 1 days), oneDayFee, "one day settlement fee");
        assertEq(midnight.settlementFee(id, 7 days), sevenDaysFee, "seven days settlement fee");
        assertEq(midnight.settlementFee(id, 30 days), thirtyDaysFee, "thirty days settlement fee");
        assertEq(midnight.settlementFee(id, 90 days), ninetyDaysFee, "ninety days settlement fee");
        assertEq(midnight.settlementFee(id, 180 days), oneEightyDaysFee, "one eighty days settlement fee");
        assertEq(midnight.settlementFee(id, 360 days), threeSixtyDaysFee, "three sixty days settlement fee");
        assertEq(midnight.settlementFee(id, 365 days), threeSixtyDaysFee, "three sixty five days settlement fee");
        assertEq(midnight.settlementFee(id, 1000 days), threeSixtyDaysFee, "one thousand days settlement fee");
    }

    function testSetSettlementFeeInvalidIndex(bytes32 id) public {
        vm.expectRevert(IMidnight.InvalidFeeIndex.selector);
        midnight.setMarketSettlementFee(id, 7, 0);
    }

    function testSetDefaultSettlementFeeInvalidIndex(address loanToken) public {
        vm.expectRevert(IMidnight.InvalidFeeIndex.selector);
        midnight.setDefaultSettlementFee(loanToken, 7, 0);
    }

    function testSetMarketSettlementFeeValueTooHigh(bytes32 id, uint256 feeTooHigh, uint256 index) public {
        index = bound(index, 0, 6);
        feeTooHigh = bound(feeTooHigh, maxSettlementFee(index) + 1, 1e18);
        vm.expectRevert(IMidnight.SettlementFeeTooHigh.selector);
        midnight.setMarketSettlementFee(id, index, feeTooHigh);
    }

    function testSetSettlementFeeNotMultipleOfFeeCbp(bytes32 id, uint256 index, uint256 fee) public {
        index = bound(index, 0, 6);
        fee = bound(fee, 1, maxSettlementFee(index));
        vm.assume(fee % 1e12 != 0);
        vm.expectRevert(IMidnight.FeeNotMultipleOfFeeCbp.selector);
        midnight.setMarketSettlementFee(id, index, fee);
    }

    function testSetDefaultSettlementFeeNotMultipleOfFeeCbp(address loanToken, uint256 index, uint256 fee) public {
        index = bound(index, 0, 6);
        fee = bound(fee, 1, maxSettlementFee(index));
        vm.assume(fee % 1e12 != 0);
        vm.expectRevert(IMidnight.FeeNotMultipleOfFeeCbp.selector);
        midnight.setDefaultSettlementFee(loanToken, index, fee);
    }

    function testSetMarketSettlementFeeMarketNotCreated(bytes32 id) public {
        vm.expectRevert(IMidnight.MarketNotCreated.selector);
        midnight.setMarketSettlementFee(id, 0, 0);
    }

    function testSetMarketContinuousFeeMarketNotCreated(bytes32 id, uint256 fee) public {
        fee = bound(fee, 0, MAX_CONTINUOUS_FEE);
        vm.expectRevert(IMidnight.MarketNotCreated.selector);
        midnight.setMarketContinuousFee(id, fee);
    }

    function testSetSettlementFeeOnlyFeeSetter(address rdm, bytes32 id) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert(IMidnight.OnlyFeeSetter.selector);
        midnight.setMarketSettlementFee(id, 0, 0);
    }

    function testSetFeeClaimerSuccess(address feeClaimer) public {
        vm.expectEmit();
        emit EventsLib.SetFeeClaimer(feeClaimer);

        midnight.setFeeClaimer(feeClaimer);
        assertEq(midnight.feeClaimer(), feeClaimer, "fee claimer set");
    }

    function testSetFeeClaimerOnlyRoleSetter(address rdm) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert(IMidnight.OnlyRoleSetter.selector);
        midnight.setFeeClaimer(makeAddr("newRecipient"));
    }

    // Default settlement fee tests

    function testSettlementFeeRevertsWhenNotCreated() public {
        vm.expectRevert(IMidnight.MarketNotCreated.selector);
        midnight.settlementFee(bytes32(0), 0);
    }

    function testSetDefaultSettlementFeeSuccess(
        address loanToken,
        uint256 postMaturityFee,
        uint256 oneDayFee,
        uint256 sevenDaysFee,
        uint256 thirtyDaysFee,
        uint256 ninetyDaysFee,
        uint256 oneEightyDaysFee,
        uint256 threeSixtyDaysFee
    ) public {
        postMaturityFee = bound(postMaturityFee, 0, maxSettlementFee(0)) / 1e12 * 1e12;
        oneDayFee = bound(oneDayFee, postMaturityFee, maxSettlementFee(1)) / 1e12 * 1e12;
        sevenDaysFee = bound(sevenDaysFee, oneDayFee, maxSettlementFee(2)) / 1e12 * 1e12;
        thirtyDaysFee = bound(thirtyDaysFee, sevenDaysFee, maxSettlementFee(3)) / 1e12 * 1e12;
        ninetyDaysFee = bound(ninetyDaysFee, thirtyDaysFee, maxSettlementFee(4)) / 1e12 * 1e12;
        oneEightyDaysFee = bound(oneEightyDaysFee, ninetyDaysFee, maxSettlementFee(5)) / 1e12 * 1e12;
        threeSixtyDaysFee = bound(threeSixtyDaysFee, oneEightyDaysFee, maxSettlementFee(6)) / 1e12 * 1e12;

        vm.expectEmit();
        emit EventsLib.SetDefaultSettlementFee(loanToken, 0, postMaturityFee);
        midnight.setDefaultSettlementFee(loanToken, 0, postMaturityFee);

        vm.expectEmit();
        emit EventsLib.SetDefaultSettlementFee(loanToken, 1, oneDayFee);
        midnight.setDefaultSettlementFee(loanToken, 1, oneDayFee);

        vm.expectEmit();
        emit EventsLib.SetDefaultSettlementFee(loanToken, 2, sevenDaysFee);
        midnight.setDefaultSettlementFee(loanToken, 2, sevenDaysFee);

        vm.expectEmit();
        emit EventsLib.SetDefaultSettlementFee(loanToken, 3, thirtyDaysFee);
        midnight.setDefaultSettlementFee(loanToken, 3, thirtyDaysFee);

        vm.expectEmit();
        emit EventsLib.SetDefaultSettlementFee(loanToken, 4, ninetyDaysFee);
        midnight.setDefaultSettlementFee(loanToken, 4, ninetyDaysFee);

        vm.expectEmit();
        emit EventsLib.SetDefaultSettlementFee(loanToken, 5, oneEightyDaysFee);
        midnight.setDefaultSettlementFee(loanToken, 5, oneEightyDaysFee);

        vm.expectEmit();
        emit EventsLib.SetDefaultSettlementFee(loanToken, 6, threeSixtyDaysFee);
        midnight.setDefaultSettlementFee(loanToken, 6, threeSixtyDaysFee);

        // touch market with this loan token
        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        Market memory market = Market({
            loanToken: loanToken,
            maturity: vm.getBlockTimestamp() + 1 days,
            collateralParams: collateralParams,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        bytes32 id = toId(market);
        midnight.touchMarket(market);

        assertEq(midnight.settlementFee(id, 0), postMaturityFee, "0 days default fee");
        assertEq(midnight.settlementFee(id, 1 days), oneDayFee, "1 day default fee");
        assertEq(midnight.settlementFee(id, 7 days), sevenDaysFee, "7 days default fee");
        assertEq(midnight.settlementFee(id, 30 days), thirtyDaysFee, "30 days default fee");
        assertEq(midnight.settlementFee(id, 90 days), ninetyDaysFee, "90 days default fee");
        assertEq(midnight.settlementFee(id, 180 days), oneEightyDaysFee, "180 days default fee");
        assertEq(midnight.settlementFee(id, 360 days), threeSixtyDaysFee, "360 days default fee");
        assertEq(midnight.settlementFee(id, 365 days), threeSixtyDaysFee, "365 days default fee");
        assertEq(midnight.settlementFee(id, 1000 days), threeSixtyDaysFee, "1000 days default fee");
    }

    function testSetDefaultSettlementFeeOnlyFeeSetter(address rdm, address loanToken) public {
        vm.assume(rdm != address(this));
        vm.prank(rdm);
        vm.expectRevert(IMidnight.OnlyFeeSetter.selector);
        midnight.setDefaultSettlementFee(loanToken, 0, 0);
    }

    function testSetDefaultSettlementFeeValidation(address loanToken, uint256 feeTooHigh, uint256 index) public {
        index = bound(index, 0, 6);
        feeTooHigh = bound(feeTooHigh, maxSettlementFee(index) + 1, 1e18);
        vm.expectRevert(IMidnight.SettlementFeeTooHigh.selector);
        midnight.setDefaultSettlementFee(loanToken, index, feeTooHigh);
    }

    function testSettlementFeeLinearInterpolation(
        uint256 settlementFee0,
        uint256 settlementFee1,
        uint256 settlementFee2,
        uint256 settlementFee3,
        uint256 settlementFee4,
        uint256 settlementFee5,
        uint256 settlementFee6
    ) public {
        settlementFee0 = bound(settlementFee0, 0, maxSettlementFee(0)) / 1e12 * 1e12;
        settlementFee1 = bound(settlementFee1, 0, maxSettlementFee(1)) / 1e12 * 1e12;
        settlementFee2 = bound(settlementFee2, 0, maxSettlementFee(2)) / 1e12 * 1e12;
        settlementFee3 = bound(settlementFee3, 0, maxSettlementFee(3)) / 1e12 * 1e12;
        settlementFee4 = bound(settlementFee4, 0, maxSettlementFee(4)) / 1e12 * 1e12;
        settlementFee5 = bound(settlementFee5, 0, maxSettlementFee(5)) / 1e12 * 1e12;
        settlementFee6 = bound(settlementFee6, 0, maxSettlementFee(6)) / 1e12 * 1e12;

        CollateralParams[] memory cols = new CollateralParams[](1);
        cols[0] = CollateralParams({
            token: address(collateralToken1), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        Market memory market = Market({
            loanToken: address(0),
            maturity: vm.getBlockTimestamp() + 1 days,
            collateralParams: cols,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        bytes32 id = toId(market);
        midnight.touchMarket(market);

        midnight.setMarketSettlementFee(id, 0, settlementFee0);
        midnight.setMarketSettlementFee(id, 1, settlementFee1);
        midnight.setMarketSettlementFee(id, 2, settlementFee2);
        midnight.setMarketSettlementFee(id, 3, settlementFee3);
        midnight.setMarketSettlementFee(id, 4, settlementFee4);
        midnight.setMarketSettlementFee(id, 5, settlementFee5);
        midnight.setMarketSettlementFee(id, 6, settlementFee6);

        // Test exact breakpoints
        assertEq(midnight.settlementFee(id, 0), settlementFee0, "0 days");
        assertEq(midnight.settlementFee(id, 1 days), settlementFee1, "1 day");
        assertEq(midnight.settlementFee(id, 7 days), settlementFee2, "7 days");
        assertEq(midnight.settlementFee(id, 30 days), settlementFee3, "30 days");
        assertEq(midnight.settlementFee(id, 90 days), settlementFee4, "90 days");
        assertEq(midnight.settlementFee(id, 180 days), settlementFee5, "180 days");
        assertEq(midnight.settlementFee(id, 360 days), settlementFee6, "360 days");

        // Test interpolation midpoint (0.5 days is between index 0 and 1)
        uint256 expectedMidpoint = (settlementFee0 * (1 days - 0.5 days) + settlementFee1 * (0.5 days)) / 1 days;
        assertEq(midnight.settlementFee(id, 0.5 days), expectedMidpoint, "Midpoint 0-1d");

        // Test interpolation midpoint (4 days is between index 1 and 2)
        uint256 expectedMid4d =
            (settlementFee1 * (7 days - 4 days) + settlementFee2 * (4 days - 1 days)) / (7 days - 1 days);
        assertEq(midnight.settlementFee(id, 4 days), expectedMid4d, "Midpoint 1-7d");

        // Test interpolation midpoint (270 days is between index 5 [180d] and index 6 [360d])
        uint256 expectedMid270d =
            (settlementFee5 * (360 days - 270 days) + settlementFee6 * (270 days - 180 days)) / (360 days - 180 days);
        assertEq(midnight.settlementFee(id, 270 days), expectedMid270d, "Midpoint 180-360d");

        // Test beyond 360 days
        assertEq(midnight.settlementFee(id, 365 days), settlementFee6, "365 days");
        assertEq(midnight.settlementFee(id, 1000 days), settlementFee6, "1000 days");
    }

    function testSetContinuousFeeOnlyFeeSetter(address rdm) public {
        vm.assume(rdm != address(this));

        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        Market memory market = Market({
            loanToken: address(loanToken),
            maturity: vm.getBlockTimestamp() + 100 days,
            collateralParams: collateralParams,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        midnight.touchMarket(market);
        bytes32 id = toId(market);

        vm.prank(rdm);
        vm.expectRevert(IMidnight.OnlyFeeSetter.selector);
        midnight.setMarketContinuousFee(id, 100);

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
        Market memory market = Market({
            loanToken: address(loanToken),
            maturity: vm.getBlockTimestamp() + 100 days,
            collateralParams: collateralParams,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        midnight.touchMarket(market);
        bytes32 id = toId(market);

        vm.expectRevert(IMidnight.ContinuousFeeTooHigh.selector);
        midnight.setMarketContinuousFee(id, fee);

        vm.expectRevert(IMidnight.ContinuousFeeTooHigh.selector);
        midnight.setDefaultContinuousFee(address(loanToken), fee);
    }

    function testSetContinuousFeeSuccess(uint256 fee, uint256 fee2) public {
        fee = bound(fee, 0, MAX_CONTINUOUS_FEE);
        fee2 = bound(fee2, 0, MAX_CONTINUOUS_FEE);
        vm.assume(fee != fee2);

        vm.expectEmit();
        emit EventsLib.SetDefaultContinuousFee(address(loanToken), fee);

        midnight.setDefaultContinuousFee(address(loanToken), fee);
        assertEq(midnight.defaultContinuousFee(address(loanToken)), fee, "default fee updated");

        CollateralParams[] memory collateralParams = new CollateralParams[](1);
        collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });
        Market memory market = Market({
            loanToken: address(loanToken),
            maturity: vm.getBlockTimestamp() + 100 days,
            collateralParams: collateralParams,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        midnight.touchMarket(market);
        bytes32 id = toId(market);

        assertEq(midnight.continuousFee(id), fee, "market inherits default fee");

        vm.expectEmit();
        emit EventsLib.SetMarketContinuousFee(id, fee2);

        midnight.setMarketContinuousFee(id, fee2);
        assertEq(midnight.continuousFee(id), fee2, "market fee updated");
    }
}
