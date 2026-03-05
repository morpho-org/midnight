// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {WAD, ORACLE_PRICE_SCALE, TIME_TO_MAX_LIF, LIQUIDATION_CURSOR_LOW} from "../src/libraries/ConstantsLib.sol";
import {Obligation, Offer, Collateral} from "../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, TICK_RANGE} from "../src/libraries/TickLib.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

uint256 constant MAX_UNITS = MAX_TEST_AMOUNT / 2;

contract LossTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;
    uint256 internal _nonce;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken1),
                    lltv: 0.75e18,
                    maxLif: maxLif(0.75e18, LIQUIDATION_CURSOR_LOW),
                    oracle: address(oracle1)
                })
            );
        obligation.rcfThreshold = type(uint256).max;

        id = toId(obligation);

        deal(address(loanToken), address(this), type(uint256).max);
    }

    function testBasicLoss(uint256 units, uint256 oraclePrice) public {
        units = bound(units, 10, MAX_UNITS);
        oraclePrice = bound(oraclePrice, 1, obligation.collaterals[0].lltv * obligation.collaterals[0].maxLif - 1);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        oracle1.setPrice(oraclePrice);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF);
        midnight.liquidate(obligation, 0, 0, 0, borrower, "");

        uint256 debt = midnight.debtOf(id, borrower);
        deal(address(loanToken), borrower, debt);
        vm.prank(borrower);
        midnight.repay(obligation, debt, borrower);

        int256 expected = _expectedBalance(id, lender, units);

        vm.prank(lender);
        midnight.withdraw(obligation, 0, lender, lender);
        assertEq(midnight.balanceOf(id, lender), expected);

        uint256 toWithdraw = uint256(expected);
        uint256 balBefore = loanToken.balanceOf(lender);
        vm.prank(lender);
        midnight.withdraw(obligation, toWithdraw, lender, lender);
        assertEq(midnight.balanceOf(id, lender), 0);
        assertEq(loanToken.balanceOf(lender) - balBefore, toWithdraw);
    }

    function testLossViewOnly(uint256 units, uint256 oraclePrice) public {
        units = bound(units, 10, MAX_UNITS);
        oraclePrice = bound(oraclePrice, 1, obligation.collaterals[0].lltv * obligation.collaterals[0].maxLif - 1);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        oracle1.setPrice(oraclePrice);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF);
        midnight.liquidate(obligation, 0, 0, 0, borrower, "");

        assertEq(midnight.balanceOf(id, lender), int256(units), "raw balance unchanged");

        int256 expected = _expectedBalance(id, lender, units);
        assertEq(midnight.balanceOfAfterLoss(id, lender), expected, "view reflects loss");
    }

    function testBalanceOfAfterLossMatchesApplyLoss(uint256 units, uint256 oraclePrice) public {
        units = bound(units, 10, MAX_UNITS);
        oraclePrice = bound(oraclePrice, 1, obligation.collaterals[0].lltv * obligation.collaterals[0].maxLif - 1);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        oracle1.setPrice(oraclePrice);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF);
        midnight.liquidate(obligation, 0, 0, 0, borrower, "");

        int256 expected = midnight.balanceOfAfterLoss(id, lender);

        vm.prank(lender);
        midnight.withdraw(obligation, 0, lender, lender);

        assertEq(midnight.balanceOf(id, lender), expected);
    }

    function testLossToZero(uint256 units) public {
        units = bound(units, 1, MAX_UNITS);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        liquidateAllDebt(borrower);

        assertEq(midnight.totalUnits(id), 0);

        vm.prank(lender);
        midnight.withdraw(obligation, 0, lender, lender);

        assertEq(midnight.balanceOf(id, lender), 0);
    }

    function testMultipleLenders(uint256 units, uint256 oraclePrice) public {
        units = bound(units, 10, MAX_UNITS);
        oraclePrice = bound(oraclePrice, 1, obligation.collaterals[0].lltv * obligation.collaterals[0].maxLif - 1);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        setupOtherUsers(obligation, units);

        oracle1.setPrice(oraclePrice);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF);
        midnight.liquidate(obligation, 0, 0, 0, borrower, "");

        int256 expected = _expectedBalance(id, lender, units);
        assertEq(midnight.balanceOfAfterLoss(id, lender), expected);
        assertEq(midnight.balanceOfAfterLoss(id, otherLender), expected);
    }

    function testNewLenderAfterLoss(uint256 units, uint256 newUnits) public {
        units = bound(units, 10, MAX_UNITS);
        newUnits = bound(newUnits, 1, MAX_UNITS);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        liquidateAllDebt(borrower);

        vm.prank(lender);
        midnight.withdraw(obligation, 0, lender, lender);
        assertEq(midnight.balanceOf(id, lender), 0);

        (address newBorrower, uint256 newBorrowerPk) = makeAddrAndKey("newBorrower");
        privateKey[newBorrower] = newBorrowerPk;
        address newLender = makeAddr("newLender");
        vm.prank(newLender);
        loanToken.approve(address(midnight), type(uint256).max);

        deal(address(loanToken), newLender, newUnits);
        collateralize(obligation, newBorrower, newUnits);

        Offer memory newBorrowerOffer;
        newBorrowerOffer.obligation = obligation;
        newBorrowerOffer.buy = false;
        newBorrowerOffer.maker = newBorrower;
        newBorrowerOffer.receiverIfMakerIsSeller = newBorrower;
        newBorrowerOffer.obligationUnits = newUnits;
        newBorrowerOffer.start = block.timestamp;
        newBorrowerOffer.expiry = block.timestamp + 200;
        newBorrowerOffer.tick = TICK_RANGE;

        take(newUnits, newLender, newBorrowerOffer);

        assertEq(midnight.balanceOf(id, newLender), int256(newUnits));
    }

    function testTwoShiftsInOneEvent() public {
        uint256 units = 1e29;

        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        liquidateAllDebt(borrower);

        (,,, uint32 shifts0,) = midnight.obligationState(id);
        assertEq(shifts0, 1);

        _createPosition(units);
        liquidateAllDebt(borrower);

        (,,, uint32 shifts1,) = midnight.obligationState(id);
        assertEq(shifts1, 3);
        assertEq(midnight.totalUnits(id), 0);

        int256 expectedLender = _expectedBalance(id, lender, units);
        assertEq(midnight.balanceOfAfterLoss(id, lender), expectedLender);

        vm.prank(lender);
        midnight.withdraw(obligation, 0, lender, lender);
        assertEq(midnight.balanceOf(id, lender), expectedLender);
    }

    function testTwoLendersWithDifferentEntryPointsGetDifferentLosses() public {
        uint256 units = 1e20;

        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        liquidateAllDebt(borrower);

        address lender1 = _createPosition(units);
        liquidateAllDebt(borrower);

        (,,, uint32 oblShifts,) = midnight.obligationState(id);
        assertEq(oblShifts, 2);

        int256 expectedLender = _expectedBalance(id, lender, units);
        assertEq(midnight.balanceOfAfterLoss(id, lender), expectedLender);

        int256 expectedLender1 = _expectedBalance(id, lender1, units);
        assertEq(midnight.balanceOfAfterLoss(id, lender1), expectedLender1);

        vm.prank(lender);
        midnight.withdraw(obligation, 0, lender, lender);
        assertEq(midnight.balanceOf(id, lender), expectedLender);

        vm.prank(lender1);
        midnight.withdraw(obligation, 0, lender1, lender1);
        assertEq(midnight.balanceOf(id, lender1), expectedLender1);
    }

    function liquidateAllDebt(address _borrower) internal {
        oracle1.setPrice(0);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF);
        midnight.liquidate(obligation, 0, 0, 0, _borrower, "");
        oracle1.setPrice(ORACLE_PRICE_SCALE);
    }

    function _expectedBalance(bytes32 _id, address user, uint256 balance) internal view returns (int256) {
        (uint128 userScale, uint32 userShifts) = midnight.loss(_id, user);
        (,, uint128 oblScale, uint32 oblShifts,) = midnight.obligationState(_id);
        uint32 shifts = oblShifts - userShifts;
        return int256(balance.mulDivDown(userScale, oblScale) >> (64 * shifts));
    }

    function _createPosition(uint256 units) internal returns (address _lender) {
        _nonce++;
        _lender = vm.addr(_nonce + 1000);

        vm.prank(_lender);
        loanToken.approve(address(midnight), type(uint256).max);
        deal(address(loanToken), _lender, units);

        collateralize(obligation, borrower, units);

        Offer memory offer;
        offer.obligation = obligation;
        offer.buy = false;
        offer.maker = borrower;
        offer.receiverIfMakerIsSeller = borrower;
        offer.obligationUnits = units;
        offer.start = block.timestamp;
        offer.expiry = block.timestamp + 200;
        offer.tick = TICK_RANGE;
        offer.group = bytes32(_nonce);

        take(units, _lender, offer);
    }
}
