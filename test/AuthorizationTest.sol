// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IMidnight, Obligation, CollateralParams, Offer} from "../src/interfaces/IMidnight.sol";
import {BaseTest} from "./BaseTest.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";

contract AuthorizationTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );

        id = toId(obligation);
    }

    function testSetAuthorization() public {
        address user = makeAddr("user");
        address authorized = makeAddr("authorized");

        assertEq(midnight.isAuthorized(user, authorized), false);

        vm.prank(user);
        midnight.setIsAuthorized(user, authorized, true);

        assertEq(midnight.isAuthorized(user, authorized), true);

        vm.prank(user);
        midnight.setIsAuthorized(user, authorized, false);

        assertEq(midnight.isAuthorized(user, authorized), false);
    }

    function testWithdrawUnauthorized() public {
        uint256 units = 1000;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        // Borrower repays
        skip(99);
        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        midnight.repay(obligation, units, borrower, hex"");

        // Attacker tries to withdraw lender's units
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(IMidnight.Unauthorized.selector);
        midnight.withdraw(obligation, units, lender, lender);
    }

    function testWithdrawCollateralUnauthorized() public {
        uint256 collateralAmount = 1000;
        address user = makeAddr("user");
        address collateralToken = obligation.collateralParams[0].token;

        deal(collateralToken, user, collateralAmount);
        vm.prank(user);
        ERC20(collateralToken).approve(address(midnight), collateralAmount);

        vm.prank(user);
        midnight.supplyCollateral(obligation, 0, collateralAmount, user);

        // Attacker tries to withdraw user's collateral
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(IMidnight.Unauthorized.selector);
        midnight.withdrawCollateral(obligation, 0, collateralAmount, user, user);
    }

    function testWithdrawAuthorized() public {
        uint256 units = 1000;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        // Borrower repays
        skip(99);
        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        midnight.repay(obligation, units, borrower, hex"");

        // Lender authorizes operator
        address operator = makeAddr("operator");
        vm.prank(lender);
        midnight.setIsAuthorized(lender, operator, true);

        // Operator can withdraw on behalf of lender
        vm.prank(operator);
        midnight.withdraw(obligation, units, lender, operator);

        assertEq(loanToken.balanceOf(operator), units);
    }

    function testWithdrawCollateralAuthorized() public {
        uint256 collateralAmount = 1000;
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address collateralToken = obligation.collateralParams[0].token;

        // User authorizes operator
        vm.prank(user);
        midnight.setIsAuthorized(user, operator, true);

        deal(collateralToken, user, collateralAmount);

        vm.prank(user);
        ERC20(collateralToken).approve(address(midnight), collateralAmount);

        vm.prank(user);
        midnight.supplyCollateral(obligation, 0, collateralAmount, user);

        // Operator can withdraw on behalf of user
        vm.prank(operator);
        midnight.withdrawCollateral(obligation, 0, collateralAmount, user, operator);

        assertEq(ERC20(collateralToken).balanceOf(operator), collateralAmount);
    }

    function testSupplyCollateralUnauthorized() public {
        uint256 collateralAmount = 1000;
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address collateralToken = obligation.collateralParams[0].token;

        deal(collateralToken, operator, collateralAmount);
        vm.prank(operator);
        ERC20(collateralToken).approve(address(midnight), collateralAmount);

        vm.prank(operator);
        vm.expectRevert(IMidnight.Unauthorized.selector);
        midnight.supplyCollateral(obligation, 0, collateralAmount, user);

        // User authorizes operator
        vm.prank(user);
        midnight.setIsAuthorized(user, operator, true);

        vm.prank(operator);
        midnight.supplyCollateral(obligation, 0, collateralAmount, user);

        assertEq(midnight.collateral(id, user, 0), collateralAmount);
    }

    function testWithdrawSelf() public {
        uint256 units = 1000;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        // Borrower repays
        skip(99);
        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        midnight.repay(obligation, units, borrower, hex"");

        // Lender can withdraw their own units (no authorization needed)
        vm.prank(lender);
        midnight.withdraw(obligation, units, lender, lender);

        assertEq(loanToken.balanceOf(lender), units);
    }

    function testWithdrawCollateralSelf() public {
        uint256 collateralAmount = 1000;
        address user = makeAddr("user");
        address collateralToken = obligation.collateralParams[0].token;

        deal(collateralToken, user, collateralAmount);
        vm.prank(user);
        ERC20(collateralToken).approve(address(midnight), collateralAmount);
        vm.prank(user);
        midnight.supplyCollateral(obligation, 0, collateralAmount, user);

        // User can withdraw their own collateral (no authorization needed)
        vm.prank(user);
        midnight.withdrawCollateral(obligation, 0, collateralAmount, user, user);

        assertEq(ERC20(collateralToken).balanceOf(user), collateralAmount);
    }

    function testTakeUnauthorized() public {
        uint256 units = 1000;
        address taker = makeAddr("taker");

        Offer memory offer;
        offer.buy = true;
        offer.maker = lender;
        offer.ratifier = address(ecrecoverRatifier);
        offer.maxUnits = units;
        offer.obligation = obligation;
        offer.expiry = block.timestamp + 200;
        offer.tick = MAX_TICK;

        deal(address(loanToken), lender, units);
        collateralize(obligation, borrower, units);

        // Attacker tries to take on behalf of taker
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(IMidnight.TakerUnauthorized.selector);
        midnight.take(units, taker, address(0), hex"", address(0), offer, sig([offer]), root([offer]), proof([offer]));
    }

    function testTakeAuthorized() public {
        uint256 units = 1000;
        address taker = makeAddr("taker");
        address operator = makeAddr("operator");

        Offer memory offer;
        offer.buy = true;
        offer.maker = lender;
        offer.ratifier = address(ecrecoverRatifier);
        offer.maxUnits = units;
        offer.obligation = obligation;
        offer.expiry = block.timestamp + 200;
        offer.tick = MAX_TICK;

        deal(address(loanToken), lender, units);
        collateralize(obligation, taker, units);

        // Taker authorizes operator
        vm.prank(taker);
        midnight.setIsAuthorized(taker, operator, true);

        // Operator can take on behalf of taker
        vm.prank(operator);
        midnight.take(units, taker, address(0), hex"", taker, offer, sig([offer]), root([offer]), proof([offer]));

        assertEq(midnight.debtOf(id, taker), units);
    }

    function testRepayAuthorization(address authorized) public {
        vm.assume(authorized != borrower);
        vm.assume(!midnight.isAuthorized(borrower, authorized));
        uint256 units = 1000;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        deal(address(loanToken), authorized, units);
        vm.prank(authorized);
        loanToken.approve(address(midnight), 0);
        vm.prank(authorized);
        loanToken.approve(address(midnight), units);

        vm.prank(authorized);
        vm.expectRevert(IMidnight.Unauthorized.selector);
        midnight.repay(obligation, units, borrower, hex"");

        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, authorized, true);

        vm.prank(authorized);
        midnight.repay(obligation, units, borrower, hex"");

        assertEq(midnight.debtOf(id, borrower), 0);
    }

    function testSetConsumedAuthorization(address user, address authorized) public {
        vm.assume(user != authorized);

        vm.prank(authorized);
        vm.expectRevert(IMidnight.Unauthorized.selector);
        midnight.setConsumed(bytes32(0), 100, user);

        vm.prank(user);
        midnight.setIsAuthorized(user, authorized, true);

        vm.prank(authorized);
        midnight.setConsumed(bytes32(0), 100, user);

        assertEq(midnight.consumed(user, bytes32(0)), 100);
    }

    function testShuffleSessionAuthorization(address user, address authorized) public {
        vm.assume(user != authorized);

        vm.prank(authorized);
        vm.expectRevert(IMidnight.Unauthorized.selector);
        midnight.shuffleSession(user);

        vm.prank(user);
        midnight.setIsAuthorized(user, authorized, true);

        vm.prank(authorized);
        midnight.shuffleSession(user);

        assertEq(midnight.session(user), keccak256(abi.encode(0, blockhash(block.number - 1))));
    }

    function testSetIsAuthorizedAuthorization(address user, address authorized, address newAuthorized) public {
        vm.assume(user != authorized);

        vm.prank(authorized);
        vm.expectRevert(IMidnight.Unauthorized.selector);
        midnight.setIsAuthorized(user, newAuthorized, true);

        vm.prank(user);
        midnight.setIsAuthorized(user, authorized, true);

        vm.prank(authorized);
        midnight.setIsAuthorized(user, newAuthorized, true);

        assertEq(midnight.isAuthorized(user, newAuthorized), true);
    }

    function testTakeSelf() public {
        uint256 units = 1000;

        Offer memory offer;
        offer.buy = true;
        offer.maker = lender;
        offer.ratifier = address(ecrecoverRatifier);
        offer.maxUnits = units;
        offer.obligation = obligation;
        offer.expiry = block.timestamp + 200;
        offer.tick = MAX_TICK;

        deal(address(loanToken), lender, units);
        collateralize(obligation, borrower, units);

        // Borrower can take for themselves (no authorization needed)
        take(units, borrower, offer);

        assertEq(midnight.debtOf(id, borrower), units);
    }
}
