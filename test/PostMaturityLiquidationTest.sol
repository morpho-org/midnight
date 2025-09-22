// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract PostMaturityLiquidationTest is BaseTest {
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

    function testLiquidateWrongSeizuresLength() public {
        vm.warp(term.maturity + 1);
        vm.expectRevert("should have all collats");
        terms.liquidate(term, new Seizure[](0), borrower, "");
    }

    function testLiquidateBeforeMaturity() public {
        // Setup
        setupBond(term, 100);
        deal(address(loanToken), address(this), 1);

        vm.warp(term.maturity - 1);

        vm.expectRevert("post maturity liquidation is after maturity");
        terms.postMaturityLiquidation(term, new Seizure[](0), borrower, "");
    }

    function testPostMaturityLiquidateBondsInput() public {
        // Setup
        setupBond(term, 100, 200, term.maturity);
        deal(address(loanToken), address(this), 1);

        vm.warp(term.maturity);

        // Test
        Seizure[] memory seizures = new Seizure[](2);
        seizures[0] = Seizure({repaidBonds: 1, seizedAssets: 0});
        seizures[1] = Seizure({repaidBonds: 0, seizedAssets: 0});
        terms.postMaturityLiquidation(term, seizures, borrower, "");
        assertEq(terms.debtOf(borrower, id), 99);
        assertEq(terms.collateralOf(borrower, id, term.collaterals[0].token), 199);
        assertEq(loanToken.balanceOf(address(this)), 0);
    }

    function testPostMaturityLiquidateCollateralInput() public {
        // Setup
        setupBond(term, 100, 200, term.maturity);
        deal(address(loanToken), address(this), 1);

        vm.warp(term.maturity);

        // Test
        Seizure[] memory seizures = new Seizure[](2);
        seizures[0] = Seizure({repaidBonds: 0, seizedAssets: 1});
        seizures[1] = Seizure({repaidBonds: 0, seizedAssets: 0});
        terms.postMaturityLiquidation(term, seizures, borrower, "");
        assertEq(terms.debtOf(borrower, id), 99);
        assertEq(terms.collateralOf(borrower, id, term.collaterals[0].token), 199);
        assertEq(loanToken.balanceOf(address(this)), 0);
    }

    function testPostMaturityLiquidateMid() public {
        // Setup
        setupBond(term, 100, 200, term.maturity);
        deal(address(loanToken), address(this), 1);

        vm.warp(term.maturity + 1551);

        // Test
        Seizure[] memory seizures = new Seizure[](2);
        seizures[0] = Seizure({repaidBonds: 1, seizedAssets: 0});
        seizures[1] = Seizure({repaidBonds: 0, seizedAssets: 0});
        terms.postMaturityLiquidation(term, seizures, borrower, "");
        assertEq(terms.debtOf(borrower, id), 99);
        assertEq(terms.collateralOf(borrower, id, term.collaterals[0].token), 198);
        assertEq(loanToken.balanceOf(address(this)), 0);
    }

    function testPostMaturityLiquidateLate() public {
        // Setup
        setupBond(term, 100, 200, term.maturity);
        deal(address(loanToken), address(this), 1);

        vm.warp(term.maturity + 3600);

        // Test
        Seizure[] memory seizures = new Seizure[](2);
        seizures[0] = Seizure({repaidBonds: 1, seizedAssets: 0});
        seizures[1] = Seizure({repaidBonds: 0, seizedAssets: 0});
        terms.postMaturityLiquidation(term, seizures, borrower, "");
        assertEq(terms.debtOf(borrower, id), 99);
        assertEq(terms.collateralOf(borrower, id, term.collaterals[0].token), 196);
        assertEq(loanToken.balanceOf(address(this)), 0);
    }
}
