// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IMidnight, Market, CollateralParams, Offer} from "../src/interfaces/IMidnight.sol";
import {BaseTest} from "./BaseTest.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";

contract AuthorizationTest is BaseTest {
    using UtilsLib for uint256;

    Market internal market;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        market.loanToken = address(loanToken);
        market.maturity = vm.getBlockTimestamp() + 100;
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );

        id = toId(market);
    }

    function testSetAuthorization() public {
        address user = makeAddr("user");
        address authorized = makeAddr("authorized");

        assertEq(midnight.isAuthorized(user, authorized), false);

        vm.expectEmit();
        emit EventsLib.SetIsAuthorized(user, authorized, true, user);

        vm.prank(user);
        midnight.setIsAuthorized(authorized, true, user);

        assertEq(midnight.isAuthorized(user, authorized), true);

        vm.expectEmit();
        emit EventsLib.SetIsAuthorized(user, authorized, false, user);

        vm.prank(user);
        midnight.setIsAuthorized(authorized, false, user);

        assertEq(midnight.isAuthorized(user, authorized), false);
    }

    function testWithdrawUnauthorized() public {
        uint256 units = 1000;
        collateralize(market, borrower, units);
        setupMarket(market, units);

        // Borrower repays
        skip(99);
        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        midnight.repay(market, units, borrower, address(0), hex"");

        // Attacker tries to withdraw lender's units
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(IMidnight.Unauthorized.selector);
        midnight.withdraw(market, units, lender, lender);
    }

    function testWithdrawCollateralUnauthorized() public {
        uint256 collateralAmount = 1000;
        address user = makeAddr("user");
        address collateralToken = market.collateralParams[0].token;

        deal(collateralToken, user, collateralAmount);
        vm.prank(user);
        ERC20(collateralToken).approve(address(midnight), collateralAmount);

        vm.prank(user);
        midnight.supplyCollateral(market, 0, collateralAmount, user);

        // Attacker tries to withdraw user's collateral
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(IMidnight.Unauthorized.selector);
        midnight.withdrawCollateral(market, 0, collateralAmount, user, user);
    }

    function testWithdrawAuthorized() public {
        uint256 units = 1000;
        collateralize(market, borrower, units);
        setupMarket(market, units);

        // Borrower repays
        skip(99);
        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        midnight.repay(market, units, borrower, address(0), hex"");

        // Lender authorizes operator
        address operator = makeAddr("operator");
        vm.prank(lender);
        midnight.setIsAuthorized(operator, true, lender);

        // Operator can withdraw on behalf of lender
        vm.prank(operator);
        midnight.withdraw(market, units, lender, operator);

        assertEq(loanToken.balanceOf(operator), units);
    }

    function testWithdrawCollateralAuthorized() public {
        uint256 collateralAmount = 1000;
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address collateralToken = market.collateralParams[0].token;

        // User authorizes operator
        vm.prank(user);
        midnight.setIsAuthorized(operator, true, user);

        deal(collateralToken, user, collateralAmount);

        vm.prank(user);
        ERC20(collateralToken).approve(address(midnight), collateralAmount);

        vm.prank(user);
        midnight.supplyCollateral(market, 0, collateralAmount, user);

        // Operator can withdraw on behalf of user
        vm.prank(operator);
        midnight.withdrawCollateral(market, 0, collateralAmount, user, operator);

        assertEq(ERC20(collateralToken).balanceOf(operator), collateralAmount);
    }

    function testSupplyCollateralUnauthorized() public {
        uint256 collateralAmount = 1000;
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address collateralToken = market.collateralParams[0].token;

        deal(collateralToken, operator, collateralAmount);
        vm.prank(operator);
        ERC20(collateralToken).approve(address(midnight), collateralAmount);

        vm.prank(operator);
        vm.expectRevert(IMidnight.Unauthorized.selector);
        midnight.supplyCollateral(market, 0, collateralAmount, user);

        // User authorizes operator
        vm.prank(user);
        midnight.setIsAuthorized(operator, true, user);

        vm.prank(operator);
        midnight.supplyCollateral(market, 0, collateralAmount, user);

        assertEq(midnight.collateral(id, user, 0), collateralAmount);
    }

    function testWithdrawSelf() public {
        uint256 units = 1000;
        collateralize(market, borrower, units);
        setupMarket(market, units);

        // Borrower repays
        skip(99);
        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        midnight.repay(market, units, borrower, address(0), hex"");

        // Lender can withdraw their own units (no authorization needed)
        vm.prank(lender);
        midnight.withdraw(market, units, lender, lender);

        assertEq(loanToken.balanceOf(lender), units);
    }

    function testWithdrawCollateralSelf() public {
        uint256 collateralAmount = 1000;
        address user = makeAddr("user");
        address collateralToken = market.collateralParams[0].token;

        deal(collateralToken, user, collateralAmount);
        vm.prank(user);
        ERC20(collateralToken).approve(address(midnight), collateralAmount);
        vm.prank(user);
        midnight.supplyCollateral(market, 0, collateralAmount, user);

        // User can withdraw their own collateral (no authorization needed)
        vm.prank(user);
        midnight.withdrawCollateral(market, 0, collateralAmount, user, user);

        assertEq(ERC20(collateralToken).balanceOf(user), collateralAmount);
    }

    function testTakeUnauthorized() public {
        uint256 units = 1000;
        address taker = makeAddr("taker");

        Offer memory offer;
        offer.buy = true;
        offer.maker = lender;
        offer.ratifier = address(dummyRatifier);
        offer.maxUnits = units;
        offer.market = market;
        offer.expiry = vm.getBlockTimestamp() + 200;
        offer.tick = MAX_TICK;

        deal(address(loanToken), lender, units);
        collateralize(market, borrower, units);

        // Attacker tries to take on behalf of taker
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(IMidnight.TakerUnauthorized.selector);
        midnight.take(offer, hex"", units, taker, address(0), address(0), hex"");
    }

    function testTakeAuthorized() public {
        uint256 units = 1000;
        address taker = makeAddr("taker");
        address operator = makeAddr("operator");

        Offer memory offer;
        offer.buy = true;
        offer.maker = lender;
        offer.ratifier = address(dummyRatifier);
        offer.maxUnits = units;
        offer.market = market;
        offer.expiry = vm.getBlockTimestamp() + 200;
        offer.tick = MAX_TICK;

        deal(address(loanToken), lender, units);
        collateralize(market, taker, units);

        // Taker authorizes operator
        vm.prank(taker);
        midnight.setIsAuthorized(operator, true, taker);

        // Operator can take on behalf of taker
        vm.prank(operator);
        midnight.take(offer, hex"", units, taker, taker, address(0), hex"");

        assertEq(midnight.debtOf(id, taker), units);
    }

    function testRepayAuthorization(address authorized) public {
        vm.assume(authorized != borrower);
        vm.assume(!midnight.isAuthorized(borrower, authorized));
        uint256 units = 1000;
        collateralize(market, borrower, units);
        setupMarket(market, units);

        deal(address(loanToken), authorized, units);
        vm.prank(authorized);
        loanToken.approve(address(midnight), 0);
        vm.prank(authorized);
        loanToken.approve(address(midnight), units);

        vm.prank(authorized);
        vm.expectRevert(IMidnight.Unauthorized.selector);
        midnight.repay(market, units, borrower, address(0), hex"");

        vm.prank(borrower);
        midnight.setIsAuthorized(authorized, true, borrower);

        vm.prank(authorized);
        midnight.repay(market, units, borrower, address(0), hex"");

        assertEq(midnight.debtOf(id, borrower), 0);
    }

    function testSetConsumedAuthorization(address user, address authorized) public {
        vm.assume(user != authorized);

        vm.prank(authorized);
        vm.expectRevert(IMidnight.Unauthorized.selector);
        midnight.setConsumed(bytes32(0), 100, user);

        vm.prank(user);
        midnight.setIsAuthorized(authorized, true, user);

        vm.prank(authorized);
        midnight.setConsumed(bytes32(0), 100, user);

        assertEq(midnight.consumed(user, bytes32(0)), 100);
    }

    function testSetIsAuthorizedAuthorization(address user, address authorized, address newAuthorized) public {
        vm.assume(user != authorized);

        vm.prank(authorized);
        vm.expectRevert(IMidnight.Unauthorized.selector);
        midnight.setIsAuthorized(newAuthorized, true, user);

        vm.prank(user);
        midnight.setIsAuthorized(authorized, true, user);

        vm.prank(authorized);
        midnight.setIsAuthorized(newAuthorized, true, user);

        assertEq(midnight.isAuthorized(user, newAuthorized), true);
    }

    function testTakeSelf() public {
        uint256 units = 1000;

        Offer memory offer;
        offer.buy = true;
        offer.maker = lender;
        offer.ratifier = address(dummyRatifier);
        offer.maxUnits = units;
        offer.market = market;
        offer.expiry = vm.getBlockTimestamp() + 200;
        offer.tick = MAX_TICK;

        deal(address(loanToken), lender, units);
        collateralize(market, borrower, units);

        // Borrower can take for themselves (no authorization needed)
        take(units, borrower, offer);

        assertEq(midnight.debtOf(id, borrower), units);
    }
}
