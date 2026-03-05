// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Collateral} from "../src/interfaces/IMidnight.sol";
import {ORACLE_PRICE_SCALE} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TICK_RANGE} from "../src/libraries/TickLib.sol";
import {BaseTest} from "./BaseTest.sol";

uint256 constant MAX_AMOUNT = type(uint128).max;

contract MaxAmountsTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken1),
                    lltv: 0.75e18,
                    maxLif: maxLif(0.75e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.rcfThreshold = 0;

        id = toId(obligation);
    }

    function testMaxAmountIsUint128Max() public pure {
        assertEq(MAX_AMOUNT, type(uint128).max);
    }

    function testTakeMaxAmount() public {
        uint256 amount = MAX_AMOUNT;

        deal(address(loanToken), lender, amount);

        vm.prank(borrower);
        midnight.setIsAuthorized(address(this), true);

        // Set a very high oracle price so a small collateral amount is sufficient.
        // With price = ORACLE_PRICE_SCALE * 1e36, 1 collateral token = 1e36 loan tokens.
        // maxDebt = collateral * 1e36 * 0.75, so ~454 tokens covers MAX_AMOUNT.
        oracle1.setPrice(ORACLE_PRICE_SCALE * 1e36);
        uint256 collateralAmount = 1000;
        deal(address(collateralToken1), address(this), collateralAmount);
        collateralToken1.approve(address(midnight), collateralAmount);
        midnight.supplyCollateral(obligation, 0, collateralAmount, borrower);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.obligationShares = type(uint256).max;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = TICK_RANGE;

        take(amount, lender, borrowerOffer);

        assertEq(midnight.totalUnits(id), amount, "total units at max");
        assertEq(midnight.debtOf(id, borrower), amount, "debt at max");
    }

    function testTakeAboveMaxAmountReverts() public {
        uint256 amount = uint256(MAX_AMOUNT) + 1;

        deal(address(loanToken), lender, amount);

        Offer memory borrowerOffer;
        borrowerOffer.obligation = obligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.obligationShares = type(uint256).max;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = TICK_RANGE;

        vm.expectRevert("uint256 overflows uint128");
        take(amount, lender, borrowerOffer);
    }

    function testSupplyCollateralMaxAmount() public {
        uint256 amount = MAX_AMOUNT;

        deal(address(collateralToken1), address(this), amount);
        collateralToken1.approve(address(midnight), amount);

        vm.prank(borrower);
        midnight.setIsAuthorized(address(this), true);

        midnight.supplyCollateral(obligation, 0, amount, borrower);

        assertEq(midnight.collateralOf(id, borrower, 0), amount, "collateral at max");
    }

    function testSupplyCollateralAboveMaxAmountReverts() public {
        uint256 amount = uint256(MAX_AMOUNT) + 1;

        deal(address(collateralToken1), address(this), amount);
        collateralToken1.approve(address(midnight), amount);

        vm.prank(borrower);
        midnight.setIsAuthorized(address(this), true);

        vm.expectRevert("uint256 overflows uint128");
        midnight.supplyCollateral(obligation, 0, amount, borrower);
    }
}
