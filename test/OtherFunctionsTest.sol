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
        setupBond(term, bonds, supply, term.maturity);

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
        setupBond(term, bonds, supply, term.maturity);

        // Test
        vm.expectRevert("Unhealthy borrower");
        terms.withdrawCollateral(term, address(collateralToken1), withdraw, borrower);
    }

    function testWithdrawCoverOk(uint256 bonds, uint256 covered, uint256 withdrawn, uint256 termLength, uint256 skipped)
        public
    {
        uint256 originalTimestamp = block.timestamp;
        bonds = bound(bonds, 0, MAX_TEST_AMOUNT);
        covered = bound(covered, 0, bonds);
        withdrawn = bound(withdrawn, 0, covered);
        termLength = bound(termLength, 1, 365 days);
        skipped = bound(skipped, 0, termLength);
        uint256 maturity = originalTimestamp + termLength;

        term.maturity = maturity;
        _testCover(bonds, covered, term.maturity);

        skip(skipped);
        vm.prank(borrower);
        terms.withdrawCover(term, withdrawn, borrower);

        assertEq(terms.coverOf(borrower, id), covered - withdrawn, "cover of");
        assertEq(terms.availableCover(id), covered - withdrawn, "available cover");
        assertEq(loanToken.balanceOf(address(terms)), covered - withdrawn, "balance of terms");
        assertEq(loanToken.balanceOf(borrower), withdrawn, "balance of lender");
    }

    function testWithdrawCoverUnhealthy(uint256 bonds, uint256 covered, uint256 withdrawn, uint256 termLength) public {
        uint256 originalTimestamp = block.timestamp;
        bonds = bound(bonds, 1, MAX_TEST_AMOUNT);
        covered = bound(covered, 1, bonds);
        withdrawn = bound(withdrawn, 1, covered);
        termLength = bound(termLength, 1, 365 days);
        uint256 maturity = originalTimestamp + termLength;

        term.maturity = maturity;
        _testCover(bonds, covered, term.maturity);

        deal(address(loanToken), borrower, bonds - covered);
        vm.prank(borrower);
        terms.supplyCover(term, bonds - covered, borrower);
        vm.prank(borrower);
        terms.withdrawCollateral(
            term, term.collaterals[0].token, terms.collateralOf(borrower, id, term.collaterals[0].token), borrower
        );
        vm.expectRevert("Unhealthy borrower");
        terms.withdrawCover(term, withdrawn, borrower);
    }

    function testWithdrawCoverAfterMaturity(
        uint256 bonds,
        uint256 covered,
        uint256 withdrawn,
        uint256 termLength,
        uint256 skipped
    ) public {
        uint256 originalTimestamp = block.timestamp;
        bonds = bound(bonds, 1, MAX_TEST_AMOUNT);
        covered = bound(covered, 1, MAX_TEST_AMOUNT);
        withdrawn = bound(withdrawn, 0, covered);
        termLength = bound(termLength, 1, 365 days);
        uint256 maturity = originalTimestamp + termLength;

        term.maturity = maturity;
        _testCover(bonds, covered, term.maturity);

        skip(termLength + bound(skipped, 1, 365 days));

        if (covered - withdrawn >= bonds) {
            vm.prank(borrower);
            terms.withdrawCover(term, withdrawn, borrower);
        } else {
            vm.expectRevert("no new debt after maturity");
            vm.prank(borrower);
            terms.withdrawCover(term, withdrawn, borrower);
        }
    }

    function testCover(uint256 bonds, uint256 covered) public {
        bonds = bound(bonds, 0, MAX_TEST_AMOUNT);
        covered = bound(covered, 0, bonds);
        _testCover(bonds, covered, term.maturity);
    }

    function _testCover(uint256 bonds, uint256 covered, uint256 maturity) public {
        id = toId(term);

        setupBond(term, bonds, maturity);

        deal(address(loanToken), address(borrower), covered);

        terms.debtOf(borrower, id);
        terms.debtAndCoveredDebtOf(borrower, id);

        vm.prank(borrower);
        terms.supplyCover(term, covered, borrower);

        if (bonds > covered) {
            assertEq(terms.debtOf(borrower, id), bonds - covered, "debt of");
        } else {
            assertEq(terms.debtOf(borrower, id), 0, "debt of");
        }
        assertEq(terms.availableCover(id), covered, "available cover");
        assertEq(loanToken.balanceOf(address(terms)), covered, "balance of terms");
        assertEq(loanToken.balanceOf(borrower), 0, "balance of borrower");
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
        assertEq(terms.availableCover(id), 0, "available cover");
        assertEq(loanToken.balanceOf(address(terms)), 0, "balance of terms");
        assertEq(loanToken.balanceOf(lender), withdraw, "balance of lender");
    }

    function testWithdrawBondsBeforeMaturity(uint256 bonds, uint256 withdraw, uint256 maturity, uint256 skipDuration)
        public
    {
        bonds = bound(bonds, 0, MAX_TEST_AMOUNT);
        withdraw = bound(withdraw, 0, bonds);
        maturity = bound(maturity, block.timestamp, block.timestamp + 365 days);
        skipDuration = bound(skipDuration, 0, maturity - block.timestamp);
        term.maturity = maturity;

        setupBond(term, bonds, maturity);

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
        assertEq(terms.availableCover(id), 0, "available cover");
        assertEq(loanToken.balanceOf(address(terms)), 0, "balance of terms");
        assertEq(loanToken.balanceOf(lender), shares, "balance of lender");
    }
}
