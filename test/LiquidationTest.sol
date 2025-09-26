// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract LiquidationTest is BaseTest {
    Term internal term;
    bytes32 internal id;

    Seizure[] internal recordedSeizures;
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
        terms.liquidate(term, new Seizure[](0), borrower, "");
    }

    function testLiquidateNoOp() public {
        setupBond(term, 100);
        oracle.setPrice(0);

        terms.liquidate(term, new Seizure[](0), borrower, "");
    }

    function testLiquidateInconsistentInput() public {
        setupBond(term, 100);
        oracle.setPrice(0);

        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaidBonds: 1, seizedAssets: 1});

        vm.expectRevert("INCONSISTENT_INPUT");
        terms.liquidate(term, seizures, borrower, "");
    }

    function testLiquidateBondsInput() public {
        // Setup
        setupBond(term, 100);
        oracle.setPrice(1e36 - 1);
        deal(address(loanToken), address(this), 1);

        // Test
        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaidBonds: 1, seizedAssets: 0});
        terms.liquidate(term, seizures, borrower, "");
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
        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaidBonds: 0, seizedAssets: 1});
        terms.liquidate(term, seizures, borrower, "");
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
        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaidBonds: 1, seizedAssets: 0});
        terms.liquidate(term, seizures, borrower, "");
        assertEq(terms.collateralOf(borrower, id, term.collaterals[0].token), 132);
        // TODO assert bad debt
    }

    function testLiquidateCallback(bytes memory data) public {
        vm.assume(data.length > 0);

        // Setup
        setupBond(term, 100);
        oracle.setPrice(1e36 - 1);
        deal(address(loanToken), address(this), 1);

        // Test
        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaidBonds: 1, seizedAssets: 0});
        terms.liquidate(term, seizures, borrower, data);

        assertEq(recordedSeizures.length, 1, "seizures length");
        assertEq(recordedSeizures[0].repaidBonds, 1, "repaid bonds");
        assertEq(recordedSeizures[0].seizedAssets, 1, "seized assets");
        assertEq(recordedBorrower, borrower, "borrower");
        assertEq(recordedLiquidator, address(this), "liquidator");
        assertEq(recordedData, data, "data");
    }

    // Check that due to roundings, even if there is bad debt it is not always possible to seize all assets or repay all
    // debt.
    function testTotalRepaidTooHigh() public {
        Oracle oracle2 = new Oracle();
        term.collaterals[1].oracle = address(oracle2);
        id = toId(term);

        setupMaxBondWithCollaterals(term, 100, 100);
        uint256 price = 1e36 * 1e18 / terms.LIQUIDATION_INCENTIVE_FACTOR() * 98 / 100;
        uint256 price2 = 1e36 * 1e18 / terms.LIQUIDATION_INCENTIVE_FACTOR();
        oracle.setPrice(price);
        oracle2.setPrice(price2);
        deal(address(loanToken), address(this), 100e18);

        Seizure[] memory seizures = new Seizure[](2);

        // Seizing all collateral repays too much debt.
        seizures[0] = Seizure({collateralIndex: 0, repaidBonds: 0, seizedAssets: 100});
        seizures[1] = Seizure({collateralIndex: 1, repaidBonds: 0, seizedAssets: 100});

        vm.expectRevert(stdError.arithmeticError);
        terms.liquidate(term, seizures, borrower, "");

        // Repaying all bonds can leave some assets behind
        seizures[0] = Seizure({collateralIndex: 0, repaidBonds: 75, seizedAssets: 0});
        seizures[1] = Seizure({collateralIndex: 1, repaidBonds: 75, seizedAssets: 0});
        vm.expectRevert(stdError.arithmeticError);
        terms.liquidate(term, seizures, borrower, "");
    }

    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) public {
        for (uint256 i = 0; i < seizures.length; i++) {
            recordedSeizures.push(seizures[i]);
        }
        recordedBorrower = borrower;
        recordedLiquidator = liquidator;
        recordedData = data;
    }
}
