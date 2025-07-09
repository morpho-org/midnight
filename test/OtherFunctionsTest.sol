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

    function testRepay(uint256 bonds, uint256 repaid) public {
        // Note that if this changes the values when the input is in the bounds, it will break withdraw tests.
        bonds = bound(bonds, 0, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, bonds);
        setupBond(term, bonds);

        vm.warp(block.timestamp + 99);

        deal(address(loanToken), address(borrower), repaid);

        vm.prank(borrower);
        terms.repayDebt(term, repaid, borrower);

        assertEq(terms.debtOf(borrower, id), bonds - repaid);
        assertEq(terms.withdrawable(id), repaid);
        assertEq(loanToken.balanceOf(address(terms)), repaid);
        assertEq(loanToken.balanceOf(borrower), 0);
    }

    function testWithdrawInconsistentInput() public {
        vm.expectRevert("INCONSISTENT_INPUT");
        terms.withdrawBond(term, 1, 1, lender);

        vm.expectRevert("INCONSISTENT_INPUT");
        terms.withdrawBond(term, 0, 0, lender);
    }

    function testWithdrawWithBonds(uint256 bonds, uint256 withdraw) public {
        // Setup
        bonds = bound(bonds, 1, MAX_TEST_AMOUNT);
        withdraw = bound(withdraw, 1, bonds);
        testRepay(bonds, withdraw);

        // Test
        vm.prank(lender);
        terms.withdrawBond(term, withdraw, 0, lender);

        assertEq(terms.bondSharesOf(lender, id), bonds - withdraw, "bondSharesOf");
        assertEq(terms.withdrawable(id), 0, "withdrawable");
        assertEq(loanToken.balanceOf(address(terms)), 0, "balance of terms");
        assertEq(loanToken.balanceOf(lender), withdraw, "balance of lender");
    }

    function testWithdrawWithShares(uint256 bonds, uint256 shares) public {
        // Setup
        bonds = bound(bonds, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, bonds);
        testRepay(bonds, shares);

        // Test
        // TODO: sharesPrice != 1
        vm.prank(lender);
        terms.withdrawBond(term, 0, shares, lender);

        assertEq(terms.bondSharesOf(lender, id), bonds - shares, "bondSharesOf");
        assertEq(terms.withdrawable(id), 0, "withdrawable");
        assertEq(loanToken.balanceOf(address(terms)), 0, "balance of terms");
        assertEq(loanToken.balanceOf(lender), shares, "balance of lender");
    }
}
