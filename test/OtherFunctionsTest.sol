// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Collateral} from "../src/interfaces/IMorphoV2.sol";

import {ERC20} from "./helpers/ERC20.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";
import {console} from "../lib/forge-std/src/console.sol";

contract OtherFunctionsTest is BaseTest {
    Obligation internal obligation;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = toId(obligation);
    }

    function testSupplyCollateral(address user, uint256 amount) public {
        vm.assume(user != address(morphoV2));
        address collateralToken = address(new ERC20("collat", "c"));
        deal(collateralToken, address(this), amount);
        ERC20(collateralToken).approve(address(morphoV2), amount);

        // Note: you can supply collaterals that are not in the obligation.
        morphoV2.supplyCollateral(obligation, collateralToken, amount, user);

        assertEq(morphoV2.collateralOf(user, id, collateralToken), amount, "collateral of");
        assertEq(ERC20(collateralToken).balanceOf(address(morphoV2)), amount, "balance of morphoV2");
    }

    function testWithdrawCollateralNoBorrow(address user, uint256 supply, uint256 withdraw) public {
        vm.assume(user != address(morphoV2));
        withdraw = bound(withdraw, 0, supply);
        address collateralToken = address(new ERC20("collat", "c"));
        deal(collateralToken, address(this), supply);
        ERC20(collateralToken).approve(address(morphoV2), supply);
        morphoV2.supplyCollateral(obligation, collateralToken, supply, user);

        morphoV2.withdrawCollateral(obligation, collateralToken, withdraw, user);

        assertEq(morphoV2.collateralOf(user, id, collateralToken), supply - withdraw, "collateral of");
        assertEq(ERC20(collateralToken).balanceOf(address(morphoV2)), supply - withdraw, "balance of morphoV2");
        assertEq(ERC20(collateralToken).balanceOf(address(this)), withdraw, "balance of this");
    }

    function testWithdrawCollateralWithBorrowHealthy(uint256 additionalCollateral, uint256 withdraw, uint256 units)
        public
    {
        units = bound(units, 0, MAX_TEST_AMOUNT);
        additionalCollateral = bound(additionalCollateral, 0, MAX_TEST_AMOUNT);
        address collateralToken = obligation.collaterals[0].token;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        deal(collateralToken, address(this), additionalCollateral);
        morphoV2.supplyCollateral(obligation, collateralToken, additionalCollateral, borrower);
        withdraw = bound(withdraw, 0, additionalCollateral);
        uint256 initialCollateral = morphoV2.collateralOf(borrower, id, collateralToken);

        morphoV2.withdrawCollateral(obligation, collateralToken, withdraw, borrower);

        assertEq(morphoV2.collateralOf(borrower, id, collateralToken), initialCollateral - withdraw, "collateral of");
        assertEq(
            ERC20(collateralToken).balanceOf(address(morphoV2)), initialCollateral - withdraw, "balance of morphoV2"
        );
        assertEq(ERC20(collateralToken).balanceOf(address(this)), withdraw, "balance of this");
    }

    function testWithdrawCollateralWithBorrowUnhealthy(uint256 additionalCollateral, uint256 withdraw, uint256 units)
        public
    {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        additionalCollateral = bound(additionalCollateral, 0, MAX_TEST_AMOUNT);
        address collateralToken = obligation.collaterals[0].token;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        deal(collateralToken, address(this), additionalCollateral);
        morphoV2.supplyCollateral(obligation, collateralToken, additionalCollateral, borrower);
        uint256 initialCollateral = morphoV2.collateralOf(borrower, id, collateralToken);
        withdraw = bound(withdraw, additionalCollateral + 1, initialCollateral);

        vm.expectRevert("Unhealthy borrower");
        morphoV2.withdrawCollateral(obligation, collateralToken, withdraw, borrower);
    }

    function testWithdrawInconsistentInput(uint256 units, uint256 shares) public {
        vm.assume(units > 0 && shares > 0);
        vm.expectRevert("INCONSISTENT_INPUT");
        morphoV2.withdraw(obligation, units, shares, lender);
    }

    function testWithdrawWithObligations(uint256 units, uint256 withdraw) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        withdraw = bound(withdraw, 1, units);
        _testRepay(units, withdraw, 0);
        vm.warp(obligation.maturity + 1);

        vm.prank(lender);
        morphoV2.withdraw(obligation, withdraw, 0, lender);

        assertEq(morphoV2.sharesOf(lender, id), units - withdraw, "obligationSharesOf");
        assertEq(morphoV2.withdrawable(id), 0, "withdrawable");
        assertEq(morphoV2.totalShares(id), units - withdraw, "totalShares");
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

        collateralize(obligation, borrower, obligationUnits);
        setupObligation(obligation, obligationUnits);

        skip(skipDuration);

        deal(address(loanToken), address(borrower), withdraw);

        vm.prank(borrower);
        morphoV2.repay(obligation, withdraw, borrower);

        // Test
        vm.prank(lender);
        vm.expectRevert("obligation maturity");
        morphoV2.withdraw(obligation, withdraw, 0, lender);
    }

    function testWithdrawWithShares(uint256 units, uint256 shares) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, units);
        _testRepay(units, shares, 0);

        // TODO: sharesPrice != 1
        vm.warp(obligation.maturity + 1);
        vm.prank(lender);
        morphoV2.withdraw(obligation, 0, shares, lender);

        assertEq(morphoV2.sharesOf(lender, id), units - shares, "obligationSharesOf");
        assertEq(morphoV2.withdrawable(id), 0, "withdrawable");
        assertEq(loanToken.balanceOf(address(morphoV2)), 0, "balance of morphoV2");
        assertEq(loanToken.balanceOf(lender), shares, "balance of lender");
    }

    function testConsume(address user, bytes32 group, uint256 amount) public {
        vm.prank(user);
        morphoV2.consume(group, amount);
        assertEq(morphoV2.consumed(user, group), amount, "consumed");
    }

    function testShuffleNonce(address user) public {
        vm.prank(user);
        morphoV2.shuffleNonce();
        assertEq(morphoV2.nonce(user), keccak256(abi.encode(0, blockhash(block.number - 1))), "nonce");
    }

    function testWithdrawRepaidUntilMaturity(
        uint256 obligationUnits,
        uint256 repaid,
        uint256 withdrawn,
        uint256 termLength,
        uint256 skipped
    ) public {
        uint256 originalTimestamp = block.timestamp;
        obligationUnits = bound(obligationUnits, 0, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, obligationUnits * 3);
        withdrawn = bound(withdrawn, 0, repaid);
        termLength = bound(termLength, 1, 365 days);
        skipped = bound(skipped, 0, termLength);
        uint256 maturity = originalTimestamp + termLength;

        obligation.maturity = maturity;
        _testRepay(obligationUnits, repaid, 0);
        skip(skipped);
        vm.prank(borrower);
        morphoV2.withdraw(obligation, withdrawn, 0, borrower);

        assertEq(morphoV2.coveredDebtOf(borrower, id), repaid - withdrawn, "covered debt of");
        assertEq(morphoV2.withdrawable(id), repaid - withdrawn, "withdrawable");
        assertEq(loanToken.balanceOf(address(morphoV2)), repaid - withdrawn, "balance of morphoV2");
        assertEq(loanToken.balanceOf(borrower), withdrawn, "balance of lender");
    }

    function testWithdrawExcessRepaidAnyTime(
        uint256 obligationUnits,
        uint256 repaid,
        uint256 withdrawn,
        uint256 termLength,
        uint256 skipped
    ) public {
        uint256 originalTimestamp = block.timestamp;
        obligationUnits = bound(obligationUnits, 0, MAX_TEST_AMOUNT);
        repaid = bound(repaid, obligationUnits, obligationUnits * 3);
        withdrawn = bound(withdrawn, 0, repaid - obligationUnits);
        termLength = bound(termLength, 1, 365 days);
        skipped = bound(skipped, 0, termLength * 3);
        uint256 maturity = originalTimestamp + termLength;

        obligation.maturity = maturity;
        _testRepay(obligationUnits, repaid, 0);

        skip(skipped);
        vm.prank(borrower);
        morphoV2.withdraw(obligation, withdrawn, 0, borrower);
        assertEq(morphoV2.coveredDebtOf(borrower, id), repaid - withdrawn, "covered debt of");
        assertEq(morphoV2.withdrawable(id), repaid - withdrawn, "withdrawable");
        assertEq(loanToken.balanceOf(address(morphoV2)), repaid - withdrawn, "balance of morphoV2");
        assertEq(loanToken.balanceOf(borrower), withdrawn, "balance of lender");
    }

    function testWithdrawCoverUnhealthy(uint256 obligationUnits, uint256 repaid, uint256 withdrawn, uint256 termLength)
        public
    {
        uint256 originalTimestamp = block.timestamp;
        obligationUnits = bound(obligationUnits, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 1, obligationUnits);
        withdrawn = bound(withdrawn, 1, repaid);
        termLength = bound(termLength, 1, 365 days);
        uint256 maturity = originalTimestamp + termLength;

        obligation.maturity = maturity;
        _testRepay(obligationUnits, repaid, 0);

        deal(address(loanToken), borrower, obligationUnits - repaid);
        vm.prank(borrower);
        morphoV2.repay(obligation, obligationUnits - repaid, borrower);
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

    function testRepay(uint256 obligationUnits, uint256 repaid) public {
        obligationUnits = bound(obligationUnits, 0, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, obligationUnits);
        _testRepay(obligationUnits, repaid, 99);
    }

    function _testRepay(uint256 obligationUnits, uint256 repaid, uint256 skipDuration) public {
        id = toId(obligation);

        collateralize(obligation, borrower, obligationUnits);
        setupObligation(obligation, obligationUnits);
        skip(skipDuration);
        deal(address(loanToken), address(borrower), repaid);

        vm.prank(borrower);
        morphoV2.repay(obligation, repaid, borrower);

        if (obligationUnits > repaid) {
            assertEq(morphoV2.debtOf(borrower, id), obligationUnits - repaid, "debt of");
        } else {
            assertEq(morphoV2.debtOf(borrower, id), 0, "debt of");
        }
        assertEq(morphoV2.withdrawable(id), repaid, "withdrawable");
        assertEq(loanToken.balanceOf(address(morphoV2)), repaid, "balance of morphoV2");
        assertEq(loanToken.balanceOf(borrower), 0, "balance of borrower");
    }
}
