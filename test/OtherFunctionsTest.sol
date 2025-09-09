// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract OtherFunctionsTest is BaseTest {
    Term internal term;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        Collateral[] memory collaterals = new Collateral[](2);
        collaterals[0] = Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle)});
        collaterals[1] = Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle)});

        // Populate collaterals one by one to avoid the unsupported memory-to-storage array assignment that breaks the
        // solc legacy pipeline.
        term.loanToken = address(loanToken);
        term.maturity = block.timestamp + 100;
        for (uint256 i = 0; i < collaterals.length; i++) {
            term.collaterals.push(collaterals[i]);
        }

        id = toId(term);
    }

    function testSupplyCollateral(address user, uint256 amount) public {
        // Setup
        ERC20 collateralToken = new ERC20("collat", "c");
        deal(address(collateralToken), address(this), amount);
        collateralToken.approve(address(terms), amount);

        // Test
        terms.supplyCollateral(term, address(collateralToken), amount, user);

        assertEq(terms.collateralOf(user, toId(term), address(collateralToken)), amount, "collateral of");
        assertEq(collateralToken.balanceOf(address(terms)), amount, "balance of terms");
        assertEq(collateralToken.balanceOf(user), 0, "balance of user");
    }

    function testWithdrawCollateralNoBorrow(address user, uint256 supply, uint256 withdraw) public {
        // Setup
        withdraw = bound(withdraw, 0, supply);
        ERC20 collateralToken = new ERC20("collat", "c");
        deal(address(collateralToken), address(this), supply);
        collateralToken.approve(address(terms), supply);
        terms.supplyCollateral(term, address(collateralToken), supply, user);

        // Test
        terms.withdrawCollateral(term, address(collateralToken), withdraw, user);

        assertEq(terms.collateralOf(user, toId(term), address(collateralToken)), supply - withdraw, "collateral of");
        assertEq(collateralToken.balanceOf(address(terms)), supply - withdraw, "balance of terms");
        assertEq(collateralToken.balanceOf(address(this)), withdraw, "balance of this");
    }

    function testWithdrawCollateralWithBorrowHealthy(uint256 supply, uint256 withdraw, uint256 bonds) public {
        // Setup
        bonds = bound(bonds, 0, MAX_TEST_AMOUNT);
        uint256 minCollateral = (bonds * 1e18 + (0.75e18 - 1)) / 0.75e18;
        supply = bound(supply, minCollateral, 1e41);
        withdraw = bound(withdraw, 0, (supply - minCollateral) / 2);
        deal(address(collateralToken1), address(this), supply);
        setupBond(term, bonds, supply);

        // Test
        terms.withdrawCollateral(term, address(collateralToken1), withdraw, borrower);

        assertEq(
            terms.collateralOf(borrower, toId(term), address(collateralToken1)), supply - withdraw, "collateral of"
        );
        assertEq(collateralToken1.balanceOf(address(terms)), supply - withdraw, "balance of terms");
        assertEq(collateralToken1.balanceOf(address(this)), withdraw, "balance of this");
    }

    function testWithdrawCollateralWithBorrowUnhealthy(uint256 supply, uint256 withdraw, uint256 bonds) public {
        // Setup
        bonds = bound(bonds, 1, MAX_TEST_AMOUNT);
        uint256 minCollateral = (bonds * 1e18 + (0.75e18 - 1)) / 0.75e18;
        supply = bound(supply, minCollateral, 1e41);
        withdraw = bound(withdraw, supply - minCollateral + 1, supply);
        deal(address(collateralToken1), address(this), supply);
        setupBond(term, bonds, supply);

        // Test
        vm.expectRevert("Unhealthy borrower");
        terms.withdrawCollateral(term, address(collateralToken1), withdraw, borrower);
    }

    function testCover(uint256 bonds, uint256 covered) public {
        // Note that if this changes the values when the input is in the bounds, it will break withdraw tests.
        bonds = bound(bonds, 0, MAX_TEST_AMOUNT);
        covered = bound(covered, 0, bonds);
        setupBond(term, bonds);

        vm.warp(block.timestamp + 99);

        deal(address(loanToken), address(borrower), covered);

        vm.prank(borrower);
        terms.supplyCover(term, covered, borrower);

        assertEq(terms.debtOf(borrower, id), bonds - covered);
        assertEq(terms.totalCover(id), covered);
        assertEq(loanToken.balanceOf(address(terms)), covered);
        assertEq(loanToken.balanceOf(borrower), 0);
    }

    function testWithdrawInconsistentInput() public {
        vm.warp(term.maturity + 1);
        vm.expectRevert("INCONSISTENT_INPUT");
        terms.withdrawBond(term, 1, 1, lender);

        vm.expectRevert("INCONSISTENT_INPUT");
        terms.withdrawBond(term, 0, 0, lender);
    }

    function testWithdrawWithBonds(uint256 bonds, uint256 withdraw) public {
        // Setup
        bonds = bound(bonds, 1, MAX_TEST_AMOUNT);
        withdraw = bound(withdraw, 1, bonds);
        testCover(bonds, withdraw);

        // Test

        vm.warp(term.maturity + 1);
        vm.prank(lender);
        terms.withdrawBond(term, withdraw, 0, lender);

        assertEq(terms.bondSharesOf(lender, id), bonds - withdraw, "bondSharesOf");
        assertEq(terms.totalCover(id), 0, "total cover");
        assertEq(loanToken.balanceOf(address(terms)), 0, "balance of terms");
        assertEq(loanToken.balanceOf(lender), withdraw, "balance of lender");
    }

    function testWithdrawBondsBeforeMaturity(uint bonds, uint withdraw, uint maturity, uint skipDuration) public {

        bonds = bound(bonds, 0, MAX_TEST_AMOUNT);
        withdraw = bound(withdraw, 0, bonds);
        maturity = bound(maturity, block.timestamp, block.timestamp + 365 days);
        skipDuration = bound(skipDuration, 0, maturity - block.timestamp);
        term.maturity = maturity;

        uint256 collateral = (bonds * 1e18 + term.collaterals[0].lltv - 1) / term.collaterals[0].lltv;

        deal(address(loanToken), lender, bonds);
        deal(address(term.collaterals[0].token), address(this), collateral);

        terms.supplyCollateral(term, address(term.collaterals[0].token), collateral, borrower);
        Offer memory borrowOffer = Offer({
            buy: false,
            offering: borrower,
            assets: bonds,
            loanToken: term.loanToken,
            collaterals: term.collaterals,
            maturity: term.maturity,
            offerStart: block.timestamp,
            offerExpiry: block.timestamp + 200,
            rate: 0,
            nonce: 0
        });

        terms.take(term, bonds, lender, borrowOffer, sig(borrowOffer, borrowerSK));

        skip(skipDuration);

        deal(address(loanToken), address(borrower), withdraw);

        vm.prank(borrower);
        terms.supplyCover(term, withdraw, borrower);

        // Test
        vm.prank(lender);
        vm.expectRevert("bond maturity");
        terms.withdrawBond(term, withdraw, 0, lender);
    }


    function testWithdrawWithShares(uint256 bonds, uint256 shares) public {
        // Setup
        bonds = bound(bonds, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, bonds);
        testCover(bonds, shares);

        // Test
        // TODO: sharesPrice != 1
        vm.warp(term.maturity + 1);
        vm.prank(lender);
        terms.withdrawBond(term, 0, shares, lender);

        assertEq(terms.bondSharesOf(lender, id), bonds - shares, "bondSharesOf");
        assertEq(terms.totalCover(id), 0, "total cover");
        assertEq(loanToken.balanceOf(address(terms)), 0, "balance of terms");
        assertEq(loanToken.balanceOf(lender), shares, "balance of lender");
    }
}
