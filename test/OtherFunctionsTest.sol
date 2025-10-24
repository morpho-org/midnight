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

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

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
        deal(obligation.collaterals[0].token, address(this), supply);
        setupObligation(obligation, obligations, supply);

        // Test
        morphoV2.withdrawCollateral(obligation, obligation.collaterals[0].token, withdraw, borrower);

        assertEq(
            morphoV2.collateralOf(borrower, toId(obligation), obligation.collaterals[0].token),
            supply - withdraw,
            "collateral of"
        );
        assertEq(
            ERC20(obligation.collaterals[0].token).balanceOf(address(morphoV2)),
            supply - withdraw,
            "balance of morphoV2"
        );
        assertEq(ERC20(obligation.collaterals[0].token).balanceOf(address(this)), withdraw, "balance of this");
    }

    function testWithdrawCollateralWithBorrowUnhealthy(uint256 supply, uint256 withdraw, uint256 obligations) public {
        // Setup
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        uint256 minCollateral = (obligations * 1e18 + (0.75e18 - 1)) / 0.75e18;
        supply = bound(supply, minCollateral, 1e41);
        withdraw = bound(withdraw, supply - minCollateral + 1, supply);
        deal(obligation.collaterals[0].token, address(this), supply);
        setupObligation(obligation, obligations, supply);

        // Test
        vm.expectRevert("Unhealthy borrower");
        morphoV2.withdrawCollateral(obligation, obligation.collaterals[0].token, withdraw, borrower);
    }

    function testRepay(uint256 obligations, uint256 repaid) public {
        // Note that if this changes the values when the input is in the bounds, it will break withdraw tests.
        obligations = bound(obligations, 0, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, obligations);
        setupObligation(obligation, obligations);

        vm.warp(block.timestamp + 99);

        deal(address(loanToken), address(borrower), repaid);

        vm.prank(borrower);
        morphoV2.repay(obligation, repaid, borrower);

        assertEq(morphoV2.debtOf(borrower, id), obligations - repaid);
        assertEq(morphoV2.withdrawable(id), repaid);
        assertEq(loanToken.balanceOf(address(morphoV2)), repaid);
        assertEq(loanToken.balanceOf(borrower), 0);
    }

    function testWithdrawInconsistentInput() public {
        vm.expectRevert("INCONSISTENT_INPUT");
        morphoV2.withdraw(obligation, 1, 1, lender);
    }

    function testWithdrawWithObligations(uint256 obligations, uint256 withdraw) public {
        // Setup
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        withdraw = bound(withdraw, 1, obligations);
        testRepay(obligations, withdraw);

        // Test
        vm.prank(lender);
        morphoV2.withdraw(obligation, withdraw, 0, lender);

        assertEq(morphoV2.sharesOf(lender, id), obligations - withdraw, "obligationSharesOf");
        assertEq(morphoV2.withdrawable(id), 0, "withdrawable");
        assertEq(morphoV2.totalShares(id), obligations - withdraw, "totalShares");
        assertEq(loanToken.balanceOf(address(morphoV2)), 0, "balance of morphoV2");
        assertEq(loanToken.balanceOf(lender), withdraw, "balance of lender");
    }

    function testWithdrawWithShares(uint256 obligations, uint256 shares) public {
        // Setup
        obligations = bound(obligations, 1, MAX_TEST_AMOUNT);
        shares = bound(shares, 1, obligations);
        testRepay(obligations, shares);

        // Test
        // TODO: sharesPrice != 1
        vm.prank(lender);
        morphoV2.withdraw(obligation, 0, shares, lender);

        assertEq(morphoV2.sharesOf(lender, id), obligations - shares, "obligationSharesOf");
        assertEq(morphoV2.withdrawable(id), 0, "withdrawable");
        assertEq(loanToken.balanceOf(address(morphoV2)), 0, "balance of morphoV2");
        assertEq(loanToken.balanceOf(lender), shares, "balance of lender");
    }

    function testConsume(address user, bytes32 group, uint256 amount) public {
        vm.prank(user);
        morphoV2.consume(group, amount);
        assertEq(morphoV2.consumed(user, group), amount, "consumed");
    }
}
