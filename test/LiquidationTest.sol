// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract LiquidationTest is BaseTest {
    Term internal term;
    bytes32 internal id;

    uint256 internal recordedRepaidBonds;
    uint256 internal recordedSeizedAssets;
    address internal recordedBorrower;
    address internal recordedLiquidator;
    bytes internal recordedData;

    function setUp() public override {
        super.setUp();

        Collateral[] memory collaterals = new Collateral[](2);
        collaterals[0] = Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle)});
        collaterals[1] = Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle)});
        collaterals = sortCollaterals(collaterals);

        // Populate collaterals one by one to avoid the unsupported memory-to-storage array assignment that breaks the
        // solc legacy pipeline.
        term.loanToken = address(loanToken);
        term.maturity = block.timestamp + 100;
        for (uint256 i = 0; i < collaterals.length; i++) {
            term.collaterals.push(collaterals[i]);
        }

        id = toId(term);
    }

    function testLiquidateHealthy() public {
        setupBond(term, 100);

        vm.expectRevert("position is healthy");
        terms.liquidate(term, address(collateralToken1), 0, 0, borrower, "");
        assertEq(terms.debtOf(borrower, id), 100);
        assertEq(terms.collateralOf(borrower, id, term.collaterals[0].token), 133);
    }

    function testLiquidateNoOp() public {
        setupBond(term, 100);
        oracle.setPrice(0);

        terms.liquidate(term, address(collateralToken1), 0, 0, borrower, "");
        assertEq(terms.debtOf(borrower, id), 100);
        assertEq(terms.collateralOf(borrower, id, term.collaterals[0].token), 133);
    }

    function testLiquidateInconsistentInput() public {
        setupBond(term, 100);
        oracle.setPrice(0);

        vm.expectRevert("INCONSISTENT_INPUT");
        terms.liquidate(term, address(collateralToken1), 1, 100, borrower, "");
        assertEq(terms.debtOf(borrower, id), 99);
        assertEq(terms.collateralOf(borrower, id, term.collaterals[0].token), 132);
    }

    function testLiquidateBondsInput() public {
        // Setup
        setupBond(term, 100);
        oracle.setPrice(1e36 - 1);
        deal(address(loanToken), address(this), 1);

        // Test
        terms.liquidate(term, address(collateralToken1), 1, 0, borrower, "");
        assertEq(terms.debtOf(borrower, id), 99);
        assertEq(terms.collateralOf(borrower, id, term.collaterals[0].token), 133);
        assertEq(loanToken.balanceOf(address(this)), 0);
    }

    function testLiquidateCollateralInput() public {
        // Setup
        setupBond(term, 100);
        oracle.setPrice(1e36 - 1);
        deal(address(loanToken), address(this), 1);

        // Test
        terms.liquidate(term, address(collateralToken1), 0, 1, borrower, "");
        assertEq(loanToken.balanceOf(address(this)), 0);
        assertEq(terms.debtOf(borrower, id), 99);
        assertEq(terms.collateralOf(borrower, id, term.collaterals[0].token), 133);
    }

    function testLiquidateBadDebt() public {
        // Setup
        setupBond(term, 100);
        oracle.setPrice(0.5e36);
        deal(address(loanToken), address(this), 1);

        // Test
        terms.liquidate(term, address(collateralToken1), 1, 0, borrower, "");
        assertEq(terms.collateralOf(borrower, id, term.collaterals[0].token), 132);
        assertEq(terms.debtOf(borrower, id), 99);
    }

    function testLiquidateCallback(bytes memory data) public {
        vm.assume(data.length > 0);

        // Setup
        setupBond(term, 100);
        oracle.setPrice(1e36 - 1);
        deal(address(loanToken), address(this), 1);

        // Test
        terms.liquidate(term, address(collateralToken1), 1, 0, borrower, data);

        assertEq(recordedRepaidBonds, 1, "repaid bonds");
        assertEq(recordedSeizedAssets, 1, "seized assets");
        assertEq(recordedBorrower, borrower, "borrower");
        assertEq(recordedLiquidator, address(this), "liquidator");
        assertEq(recordedData, data, "data");
    }

    function onLiquidate(
        uint256 repaidBonds,
        uint256 seizedAssets,
        address borrower,
        address liquidator,
        bytes memory data
    ) public {
        recordedRepaidBonds = repaidBonds;
        recordedSeizedAssets = seizedAssets;
        recordedBorrower = borrower;
        recordedLiquidator = liquidator;
        recordedData = data;
    }
}
