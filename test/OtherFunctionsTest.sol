// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {ERC20} from "./helpers/ERC20.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";

contract OtherFunctionsTest is BaseTest {
    Obligation internal obligation;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        Collateral[] memory collaterals = new Collateral[](2);
        collaterals[0] = Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle)});
        collaterals[1] = Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle)});

        // Populate collaterals one by one to avoid the unsupported memory-to-storage array assignment that breaks the
        // solc legacy pipeline.
        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        for (uint256 i = 0; i < collaterals.length; i++) {
            obligation.collaterals.push(collaterals[i]);
        }

        id = toId(obligation);
    }

    function testSupplyCollateral(address user, uint256 amount) public {
        vm.assume(user != address(morphoV2));
        // Setup
        ERC20 collateralToken = new ERC20("collat", "c");
        deal(address(collateralToken), address(this), amount);
        collateralToken.approve(address(morphoV2), amount);

        // Test
        morphoV2.supplyCollateral(obligation, address(collateralToken), amount, user);
        assertEq(morphoV2.collateralOf(user, toId(obligation), address(collateralToken)), amount, "collateral of");
        assertEq(collateralToken.balanceOf(address(morphoV2)), amount, "balance of morphoV2");
    }

    function testWithdrawCollateralNoBorrow(address user, uint256 supply, uint256 withdraw) public {
        // Setup
        withdraw = bound(withdraw, 0, supply);
        ERC20 collateralToken = new ERC20("collat", "c");
        deal(address(collateralToken), address(this), supply);
        collateralToken.approve(address(morphoV2), supply);
        morphoV2.supplyCollateral(obligation, address(collateralToken), supply, user);

        // Test
        morphoV2.withdrawCollateral(obligation, address(collateralToken), withdraw, user);

        assertEq(
            morphoV2.collateralOf(user, toId(obligation), address(collateralToken)), supply - withdraw, "collateral of"
        );
        assertEq(collateralToken.balanceOf(address(morphoV2)), supply - withdraw, "balance of morphoV2");
        assertEq(collateralToken.balanceOf(address(this)), withdraw, "balance of this");
    }

    function testWithdrawCollateralWithBorrowHealthy(uint256 supply, uint256 withdraw, uint256 obligations) public {
        // Setup
        obligations = bound(obligations, 0, MAX_TEST_AMOUNT);
        uint256 minCollateral = (obligations * 1e18 + (0.75e18 - 1)) / 0.75e18;
        supply = bound(supply, minCollateral, 1e41);
        withdraw = bound(withdraw, 0, (supply - minCollateral) / 2);
        deal(address(collateralToken1), address(this), supply);
        setupObligation(obligation, obligations, supply, obligation.maturity);

        // Test
        morphoV2.withdrawCollateral(obligation, address(collateralToken1), withdraw, borrower);

        assertEq(
            morphoV2.collateralOf(borrower, toId(obligation), address(collateralToken1)),
            supply - withdraw,
            "collateral of"
        );
        assertEq(collateralToken1.balanceOf(address(morphoV2)), supply - withdraw, "balance of morphoV2");
        assertEq(collateralToken1.balanceOf(address(this)), withdraw, "balance of this");
    }

    function testWithdrawCollateralWithBorrowUnhealthy(uint256 supply, uint256 withdraw, uint256 obligations) public {
        // Setup
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        uint256 minCollateral = (obligations * 1e18 + (0.75e18 - 1)) / 0.75e18;
        supply = bound(supply, minCollateral, 1e41);
        withdraw = bound(withdraw, supply - minCollateral + 1, supply);
        deal(address(collateralToken1), address(this), supply);
        setupObligation(obligation, obligations, supply, obligation.maturity);

        // Test
        vm.expectRevert("Unhealthy borrower");
        morphoV2.withdrawCollateral(obligation, address(collateralToken1), withdraw, borrower);
    }

    function testWithdrawAnyCoverUntilMaturity(
        uint256 obligationUnits,
        uint256 covered,
        uint256 withdrawn,
        uint256 termLength,
        uint256 skipped
    ) public {
        uint256 originalTimestamp = block.timestamp;
        obligationUnits = bound(obligationUnits, 0, MAX_TEST_AMOUNT);
        covered = bound(covered, 0, obligationUnits * 3);
        withdrawn = bound(withdrawn, 0, covered);
        termLength = bound(termLength, 1, 365 days);
        skipped = bound(skipped, 0, termLength);
        uint256 maturity = originalTimestamp + termLength;

        obligation.maturity = maturity;
        _testCover(obligationUnits, covered, obligation.maturity);

        skip(skipped);
        vm.prank(borrower);
        morphoV2.withdraw(obligation, withdrawn, 0, borrower);

        assertEq(morphoV2.coveredDebtOf(borrower, id), covered - withdrawn, "cover of");
        assertEq(morphoV2.withdrawable(id), covered - withdrawn, "available cover");
        assertEq(loanToken.balanceOf(address(morphoV2)), covered - withdrawn, "balance of morphoV2");
        assertEq(loanToken.balanceOf(borrower), withdrawn, "balance of lender");
    }

    function testWithdrawExcessCoverAnyTime(
        uint256 obligationUnits,
        uint256 covered,
        uint256 withdrawn,
        uint256 termLength,
        uint256 skipped
    ) public {
        uint256 originalTimestamp = block.timestamp;
        obligationUnits = bound(obligationUnits, 0, MAX_TEST_AMOUNT);
        covered = bound(covered, obligationUnits, obligationUnits * 3);
        withdrawn = bound(withdrawn, 0, covered - obligationUnits);
        termLength = bound(termLength, 1, 365 days);
        skipped = bound(skipped, 0, termLength * 3);
        uint256 maturity = originalTimestamp + termLength;

        obligation.maturity = maturity;
        _testCover(obligationUnits, covered, obligation.maturity);

        skip(skipped);
        vm.prank(borrower);
        morphoV2.withdraw(obligation, withdrawn, 0, borrower);

        assertEq(morphoV2.coveredDebtOf(borrower, id), covered - withdrawn, "cover of");
        assertEq(morphoV2.withdrawable(id), covered - withdrawn, "available cover");
        assertEq(loanToken.balanceOf(address(morphoV2)), covered - withdrawn, "balance of morphoV2");
        assertEq(loanToken.balanceOf(borrower), withdrawn, "balance of lender");
    }

    function testWithdrawCoverUnhealthy(
        uint256 obligationUnits,
        uint256 covered,
        uint256 withdrawn,
        uint256 termLength
    ) public {
        uint256 originalTimestamp = block.timestamp;
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT);
        covered = bound(covered, 1, obligationUnits);
        withdrawn = bound(withdrawn, 1, covered);
        termLength = bound(termLength, 1, 365 days);
        uint256 maturity = originalTimestamp + termLength;

        obligation.maturity = maturity;
        _testCover(obligationUnits, covered, obligation.maturity);

        deal(address(loanToken), borrower, obligationUnits - covered);
        vm.prank(borrower);
        morphoV2.repay(obligation, obligationUnits - covered, borrower);
        vm.prank(borrower);
        morphoV2.withdrawCollateral(
            obligation,
            obligation.collaterals[0].token,
            morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token),
            borrower
        );
        vm.expectRevert("Unhealthy borrower");
        morphoV2.withdraw(obligation, withdrawn, 0, borrower);
    }

    function _testCover(uint256 obligationUnits, uint256 covered, uint256 maturity) public {
        id = toId(obligation);

        setupObligation(obligation, obligationUnits, maturity);

        deal(address(loanToken), address(borrower), covered);

        vm.prank(borrower);
        morphoV2.repay(obligation, covered, borrower);

        if (obligationUnits > covered) {
            assertEq(morphoV2.debtOf(borrower, id), obligationUnits - covered, "debt of");
        } else {
            assertEq(morphoV2.debtOf(borrower, id), 0, "debt of");
        }
        assertEq(morphoV2.withdrawable(id), covered, "available cover");
        assertEq(loanToken.balanceOf(address(morphoV2)), covered, "balance of morphoV2");
        assertEq(loanToken.balanceOf(borrower), 0, "balance of borrower");
    }

    function testWithdrawInconsistentInput() public {
        vm.warp(obligation.maturity + 1);
        vm.expectRevert("INCONSISTENT_INPUT");
        morphoV2.withdraw(obligation, 1, 1, lender);
    }

    function testWithdrawWithObligations(uint256 obligations, uint256 withdraw) public {
        // Setup
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        withdraw = bound(withdraw, 1, obligations);
        _testCover(obligations, withdraw, obligation.maturity);

        // Test
        vm.warp(obligation.maturity + 1);
        vm.prank(lender);
        morphoV2.withdraw(obligation, withdraw, 0, lender);

        assertEq(morphoV2.sharesOf(lender, id), obligations - withdraw, "obligationSharesOf");
        assertEq(morphoV2.withdrawable(id), 0, "available cover");
        assertEq(morphoV2.totalShares(id), obligations - withdraw, "totalShares");
        assertEq(loanToken.balanceOf(address(morphoV2)), 0, "balance of morphoV2");
        assertEq(loanToken.balanceOf(lender), withdraw, "balance of lender");
    }

    function testWithdrawObligationsBeforeMaturity(
        uint256 obligationUnits,
        uint256 withdraw,
        uint256 maturity,
        uint256 skipDuration
    ) public {
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT);
        withdraw = bound(withdraw, 0, obligationUnits);
        maturity = bound(maturity, block.timestamp, block.timestamp + 365 days);
        skipDuration = bound(skipDuration, 0, maturity - block.timestamp);
        obligation.maturity = maturity;

        setupObligation(obligation, obligationUnits, maturity);

        skip(skipDuration);

        deal(address(loanToken), address(borrower), withdraw);

        vm.prank(borrower);
        morphoV2.repay(obligation, withdraw, borrower);

        // Test
        vm.prank(lender);
        vm.expectRevert("obligation maturity");
        morphoV2.withdraw(obligation, withdraw, 0, lender);
    }

    function testWithdrawWithShares(uint256 obligations, uint256 shares) public {
        // Setup
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, obligations);
        _testCover(obligations, shares, obligation.maturity);

        // Test
        // TODO: sharesPrice != 1
        vm.warp(obligation.maturity + 1);
        vm.prank(lender);
        morphoV2.withdraw(obligation, 0, shares, lender);

        assertEq(morphoV2.sharesOf(lender, id), obligations - shares, "obligationSharesOf");
        assertEq(morphoV2.withdrawable(id), 0, "available cover");
        assertEq(loanToken.balanceOf(address(morphoV2)), 0, "balance of morphoV2");
        assertEq(loanToken.balanceOf(lender), shares, "balance of lender");
    }
}
