// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Collateral, Offer} from "../src/interfaces/IMorphoV2.sol";
import {BaseTest} from "./BaseTest.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {TICK_RANGE} from "../src/libraries/TickLib.sol";

contract AuthorizationTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));

        id = toId(obligation);
    }

    function testSetAuthorization() public {
        address user = makeAddr("user");
        address authorized = makeAddr("authorized");

        assertEq(morphoV2.isAuthorized(user, authorized), false);

        vm.prank(user);
        morphoV2.setIsAuthorized(authorized, true);

        assertEq(morphoV2.isAuthorized(user, authorized), true);

        vm.prank(user);
        morphoV2.setIsAuthorized(authorized, false);

        assertEq(morphoV2.isAuthorized(user, authorized), false);
    }

    function testWithdrawUnauthorized() public {
        uint256 units = 1000;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        // Borrower repays
        skip(99);
        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        morphoV2.repay(obligation, units, borrower);

        // Attacker tries to withdraw lender's shares
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert("UNAUTHORIZED");
        morphoV2.withdraw(obligation, units, 0, lender);
    }

    function testWithdrawCollateralUnauthorized() public {
        uint256 collateralAmount = 1000;
        address user = makeAddr("user");
        address collateralToken = address(new ERC20("collat", "c"));

        deal(collateralToken, address(this), collateralAmount);
        ERC20(collateralToken).approve(address(morphoV2), collateralAmount);
        morphoV2.supplyCollateral(obligation, collateralToken, collateralAmount, user);

        // Attacker tries to withdraw user's collateral
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert("UNAUTHORIZED");
        morphoV2.withdrawCollateral(obligation, collateralToken, collateralAmount, user);
    }

    function testWithdrawAuthorized() public {
        uint256 units = 1000;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        // Borrower repays
        skip(99);
        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        morphoV2.repay(obligation, units, borrower);

        // Lender authorizes operator
        address operator = makeAddr("operator");
        vm.prank(lender);
        morphoV2.setIsAuthorized(operator, true);

        // Operator can withdraw on behalf of lender
        vm.prank(operator);
        morphoV2.withdraw(obligation, units, 0, lender);

        assertEq(loanToken.balanceOf(operator), units);
    }

    function testWithdrawCollateralAuthorized() public {
        uint256 collateralAmount = 1000;
        address user = makeAddr("user");
        address operator = makeAddr("operator");
        address collateralToken = address(new ERC20("collat", "c"));

        deal(collateralToken, address(this), collateralAmount);
        ERC20(collateralToken).approve(address(morphoV2), collateralAmount);
        morphoV2.supplyCollateral(obligation, collateralToken, collateralAmount, user);

        // User authorizes operator
        vm.prank(user);
        morphoV2.setIsAuthorized(operator, true);

        // Operator can withdraw on behalf of user
        vm.prank(operator);
        morphoV2.withdrawCollateral(obligation, collateralToken, collateralAmount, user);

        assertEq(ERC20(collateralToken).balanceOf(operator), collateralAmount);
    }

    function testWithdrawSelf() public {
        uint256 units = 1000;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        // Borrower repays
        skip(99);
        deal(address(loanToken), borrower, units);
        vm.prank(borrower);
        morphoV2.repay(obligation, units, borrower);

        // Lender can withdraw their own shares (no authorization needed)
        vm.prank(lender);
        morphoV2.withdraw(obligation, units, 0, lender);

        assertEq(loanToken.balanceOf(lender), units);
    }

    function testWithdrawCollateralSelf() public {
        uint256 collateralAmount = 1000;
        address user = makeAddr("user");
        address collateralToken = address(new ERC20("collat", "c"));

        deal(collateralToken, user, collateralAmount);
        vm.prank(user);
        ERC20(collateralToken).approve(address(morphoV2), collateralAmount);
        vm.prank(user);
        morphoV2.supplyCollateral(obligation, collateralToken, collateralAmount, user);

        // User can withdraw their own collateral (no authorization needed)
        vm.prank(user);
        morphoV2.withdrawCollateral(obligation, collateralToken, collateralAmount, user);

        assertEq(ERC20(collateralToken).balanceOf(user), collateralAmount);
    }

    function testTakeUnauthorized() public {
        uint256 assets = 1000;
        address taker = makeAddr("taker");

        Offer memory offer;
        offer.buy = true;
        offer.maker = lender;
        offer.assets = assets;
        offer.obligation = obligation;
        offer.expiry = block.timestamp + 200;
        offer.tick = TICK_RANGE;

        deal(address(loanToken), lender, assets);
        collateralize(obligation, borrower, assets);

        // Attacker tries to take on behalf of taker
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert("UNAUTHORIZED");
        morphoV2.take(assets, 0, 0, 0, taker, offer, sig([offer]), root([offer]), proof([offer]), address(0), hex"");
    }

    function testTakeAuthorized() public {
        uint256 assets = 1000;
        address taker = makeAddr("taker");
        address operator = makeAddr("operator");

        Offer memory offer;
        offer.buy = true;
        offer.maker = lender;
        offer.assets = assets;
        offer.obligation = obligation;
        offer.expiry = block.timestamp + 200;
        offer.tick = TICK_RANGE;

        deal(address(loanToken), lender, assets);
        collateralize(obligation, taker, assets);

        // Taker authorizes operator
        vm.prank(taker);
        morphoV2.setIsAuthorized(operator, true);

        // Operator can take on behalf of taker
        vm.prank(operator);
        morphoV2.take(assets, 0, 0, 0, taker, offer, sig([offer]), root([offer]), proof([offer]), address(0), hex"");

        assertEq(morphoV2.debtOf(id, taker), assets);
    }

    function testTakeSelf() public {
        uint256 assets = 1000;

        Offer memory offer;
        offer.buy = true;
        offer.maker = lender;
        offer.assets = assets;
        offer.obligation = obligation;
        offer.expiry = block.timestamp + 200;
        offer.tick = TICK_RANGE;

        deal(address(loanToken), lender, assets);
        collateralize(obligation, borrower, assets);

        // Borrower can take for themselves (no authorization needed)
        take(assets, 0, 0, 0, borrower, offer);

        assertEq(morphoV2.debtOf(id, borrower), assets);
    }
}
