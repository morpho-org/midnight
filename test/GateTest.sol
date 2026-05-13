// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IMidnight, Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {IEnterGate, ILiquidatorGate} from "../src/interfaces/IGate.sol";
import {LIQUIDATION_CURSOR_LOW, ORACLE_PRICE_SCALE} from "../src/libraries/ConstantsLib.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";
import {Oracle} from "./helpers/Oracle.sol";

contract WhitelistGate is IEnterGate, ILiquidatorGate {
    mapping(address => bool) public whitelisted;

    function setWhitelisted(address account, bool status) external {
        whitelisted[account] = status;
    }

    function canIncreaseCredit(address account) external view returns (bool) {
        return whitelisted[account];
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return whitelisted[account];
    }

    function canLiquidate(address account) external view returns (bool) {
        return whitelisted[account];
    }
}

contract GateTest is BaseTest {
    WhitelistGate internal gate;
    Market internal market;
    Market internal gatedMarket;
    bytes32 internal gatedId;
    Offer internal lenderOffer;
    Offer internal borrowerOffer;

    function setUp() public override {
        super.setUp();

        gate = new WhitelistGate();

        market.loanToken = address(loanToken);
        market.maturity = block.timestamp + 100;
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    oracle: address(oracle1),
                    maxLif: maxLif(0.77e18, LIQUIDATION_CURSOR_LOW)
                })
            );
        market.collateralParams = sortCollateralParams(market.collateralParams);

        gatedMarket.loanToken = address(loanToken);
        gatedMarket.maturity = block.timestamp + 100;
        gatedMarket.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    oracle: address(oracle1),
                    maxLif: maxLif(0.77e18, LIQUIDATION_CURSOR_LOW)
                })
            );
        gatedMarket.collateralParams = sortCollateralParams(gatedMarket.collateralParams);
        gatedMarket.enterGate = address(gate);
        gatedMarket.liquidatorGate = address(gate);

        gatedId = toId(gatedMarket);

        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.maxUnits = type(uint256).max;
        lenderOffer.market = gatedMarket;
        lenderOffer.ratifier = address(ecrecoverRatifier);
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = MAX_TICK;

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.maxUnits = type(uint256).max;
        borrowerOffer.market = gatedMarket;
        borrowerOffer.ratifier = address(ecrecoverRatifier);
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = MAX_TICK;

        deal(address(loanToken), lender, type(uint256).max);
    }

    // --- Enter gate tests ---

    function testEnterGateBlocksNonWhitelistedBuyer(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT * 3 / 4);
        collateralize(gatedMarket, borrower, units);

        gate.setWhitelisted(borrower, true);

        vm.expectRevert(IMidnight.BuyerGatedFromIncreasingCredit.selector);
        take(units, lender, borrowerOffer);
    }

    function testEnterGateBlocksNonWhitelistedSeller(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT * 3 / 4);
        collateralize(gatedMarket, borrower, units);

        gate.setWhitelisted(lender, true);

        vm.expectRevert(IMidnight.SellerGatedFromIncreasingDebt.selector);
        take(units, borrower, lenderOffer);
    }

    function testEnterGateAllowsWhitelistedUsers(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT * 3 / 4);
        collateralize(gatedMarket, borrower, units);

        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        take(units, lender, borrowerOffer);

        assertGt(midnight.creditOf(gatedId, lender), 0, "lender should have credit");
        assertGt(midnight.debtOf(gatedId, borrower), 0, "borrower should have debt");
    }

    function testEnterGateAllowsTakeWhenLenderHadCreditBefore(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);
        collateralize(gatedMarket, borrower, units);
        take(units, lender, borrowerOffer);

        assertGt(midnight.creditOf(gatedId, lender), 0, "lender should already have credit");

        gate.setWhitelisted(lender, false);
        gate.setWhitelisted(borrower, false);

        take(0, otherBorrower, lenderOffer);
    }

    function testEnterGateAllowsTakeWhenBorrowerHadDebtBefore(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);
        collateralize(gatedMarket, borrower, units);
        take(units, lender, borrowerOffer);

        assertGt(midnight.debtOf(gatedId, borrower), 0, "borrower should already have debt");

        gate.setWhitelisted(lender, false);
        gate.setWhitelisted(borrower, false);

        take(0, otherLender, borrowerOffer);
    }

    // --- No gate check on exit  ---

    function testNoEnterGateCheckWhenBorrowerIsExitingBorrower(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);
        gate.setWhitelisted(otherBorrower, true);

        collateralize(gatedMarket, borrower, units);
        take(units, lender, borrowerOffer);

        Offer memory otherBorrowerOffer;
        otherBorrowerOffer.buy = false;
        otherBorrowerOffer.maker = otherBorrower;
        otherBorrowerOffer.receiverIfMakerIsSeller = otherBorrower;
        otherBorrowerOffer.maxUnits = type(uint256).max;
        otherBorrowerOffer.market = gatedMarket;
        otherBorrowerOffer.ratifier = address(ecrecoverRatifier);
        otherBorrowerOffer.expiry = block.timestamp + 200;
        otherBorrowerOffer.tick = MAX_TICK;

        collateralize(gatedMarket, otherBorrower, units);

        gate.setWhitelisted(borrower, false);

        take(units, borrower, otherBorrowerOffer);

        assertEq(midnight.debtOf(gatedId, borrower), 0, "borrower should have exited debt");
    }

    function testNoGateCheckWhenBothExit(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT / 2);

        gate.setWhitelisted(otherLender, true);
        gate.setWhitelisted(otherBorrower, true);

        deal(address(loanToken), otherLender, units);
        collateralize(gatedMarket, otherBorrower, units);

        Offer memory otherLenderOffer;
        otherLenderOffer.buy = true;
        otherLenderOffer.maker = otherLender;
        otherLenderOffer.maxUnits = type(uint256).max;
        otherLenderOffer.market = gatedMarket;
        otherLenderOffer.ratifier = address(ecrecoverRatifier);
        otherLenderOffer.expiry = block.timestamp + 200;
        otherLenderOffer.tick = MAX_TICK;

        take(units, otherBorrower, otherLenderOffer);

        gate.setWhitelisted(otherLender, false);
        gate.setWhitelisted(otherBorrower, false);

        // Both parties exit
        Offer memory exitOffer;
        exitOffer.buy = false;
        exitOffer.maker = otherLender;
        exitOffer.receiverIfMakerIsSeller = otherLender;
        exitOffer.maxUnits = type(uint256).max;
        exitOffer.market = gatedMarket;
        exitOffer.ratifier = address(ecrecoverRatifier);
        exitOffer.expiry = block.timestamp + 200;
        exitOffer.tick = MAX_TICK;

        deal(address(loanToken), otherBorrower, units);
        take(units, otherBorrower, exitOffer);

        assertEq(midnight.debtOf(gatedId, otherBorrower), 0, "otherBorrower should have exited");
    }

    function testNoGateCheckOnRepay(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        collateralize(gatedMarket, borrower, units);
        take(units, lender, borrowerOffer);

        gate.setWhitelisted(borrower, false);

        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        midnight.repay(gatedMarket, units, borrower, address(0), hex"");

        assertEq(midnight.debtOf(gatedId, borrower), 0, "borrower should have repaid");
    }

    function testNoGateCheckOnWithdraw(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);

        collateralize(gatedMarket, borrower, units);
        take(units, lender, borrowerOffer);

        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        midnight.repay(gatedMarket, units, borrower, address(0), hex"");

        gate.setWhitelisted(lender, false);

        vm.prank(lender);
        midnight.withdraw(gatedMarket, units, lender, lender);

        assertEq(midnight.creditOf(gatedId, lender), 0, "lender should have withdrawn");
    }

    // --- Liquidator gate tests ---

    function testLiquidatorGateOnLiquidation(uint256 units, bool isWhitelisted) public {
        units = bound(units, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);
        gate.setWhitelisted(liquidator, isWhitelisted);

        collateralize(gatedMarket, borrower, units);
        take(units, lender, borrowerOffer);

        Oracle(gatedMarket.collateralParams[0].oracle).setPrice(ORACLE_PRICE_SCALE / 2);

        deal(address(loanToken), liquidator, units);
        vm.prank(liquidator);
        if (!isWhitelisted) vm.expectRevert(IMidnight.LiquidatorGatedFromLiquidating.selector);
        midnight.liquidate(gatedMarket, 0, 1, 0, borrower, address(this), address(0), "");
    }

    function testLiquidatorGateOnBadDebt(uint256 units, bool isWhitelisted) public {
        units = bound(units, 1, MAX_TEST_AMOUNT * 3 / 4);
        gate.setWhitelisted(lender, true);
        gate.setWhitelisted(borrower, true);
        gate.setWhitelisted(liquidator, isWhitelisted);

        collateralize(gatedMarket, borrower, units);
        take(units, lender, borrowerOffer);

        Oracle(gatedMarket.collateralParams[0].oracle).setPrice(0);

        vm.prank(liquidator);
        if (!isWhitelisted) vm.expectRevert(IMidnight.LiquidatorGatedFromLiquidating.selector);
        midnight.liquidate(gatedMarket, 0, 0, 0, borrower, address(this), address(0), "");
    }

    // --- Default (no gate) tests ---

    function testNoGateMeansUnrestricted(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT * 3 / 4);
        collateralize(market, borrower, units);

        Offer memory ungatedLenderOffer;
        ungatedLenderOffer.buy = true;
        ungatedLenderOffer.maker = lender;
        ungatedLenderOffer.maxUnits = type(uint256).max;
        ungatedLenderOffer.market = market;
        ungatedLenderOffer.ratifier = address(ecrecoverRatifier);
        ungatedLenderOffer.expiry = block.timestamp + 200;
        ungatedLenderOffer.tick = MAX_TICK;

        take(units, borrower, ungatedLenderOffer);

        bytes32 ungatedId = toId(market);
        assertGt(midnight.debtOf(ungatedId, borrower), 0);
    }

    // --- Market identity tests ---

    function testDifferentGatesProduceDifferentIds() public view {
        bytes32 ungatedId = toId(market);
        assertNotEq(ungatedId, gatedId, "gated and ungated markets should have different IDs");
    }
}
