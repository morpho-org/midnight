// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract LiquidationTest is BaseTest {
    Obligation internal obligation;
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
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        for (uint256 i = 0; i < collaterals.length; i++) {
            obligation.collaterals.push(collaterals[i]);
        }

        id = toId(obligation);
    }

    function testLiquidateHealthy() public {
        setupObligation(obligation, 100);

        vm.expectRevert("position is healthy");
        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateNoOp() public {
        setupObligation(obligation, 100);
        oracle.setPrice(0);

        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateInconsistentInput() public {
        setupObligation(obligation, 100);
        oracle.setPrice(0);

        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 1, seized: 1});

        vm.expectRevert("INCONSISTENT_INPUT");
        morphoV2.liquidate(obligation, seizures, borrower, "");
    }

    function testLiquidateObligationUnitsInput() public {
        // Setup
        setupObligation(obligation, 100);
        oracle.setPrice(1e36 - 1);
        deal(address(loanToken), address(this), 1);

        // Test
        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 1, seized: 0});
        morphoV2.liquidate(obligation, seizures, borrower, "");
        assertEq(morphoV2.debtOf(borrower, id), 99);
        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), 133);
        assertEq(loanToken.balanceOf(address(this)), 0);
    }

    function testLiquidateCollateralInput() public {
        // Setup
        setupObligation(obligation, 100);
        oracle.setPrice(1e36 - 1);
        deal(address(loanToken), address(this), 1);

        // Test
        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 0, seized: 1});
        morphoV2.liquidate(obligation, seizures, borrower, "");
        assertEq(loanToken.balanceOf(address(this)), 0);
        assertEq(morphoV2.debtOf(borrower, id), 99);
        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), 133);
    }

    function testLiquidateBadDebt() public {
        // Setup
        setupObligation(obligation, 100);
        oracle.setPrice(0.5e36);
        deal(address(loanToken), address(this), 1);

        // Test
        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 1, seized: 0});
        morphoV2.liquidate(obligation, seizures, borrower, "");
        assertEq(morphoV2.collateralOf(borrower, id, obligation.collaterals[0].token), 132);
        // TODO assert bad debt
    }

    function testLiquidateCallback(bytes memory data) public {
        vm.assume(data.length > 0);

        // Setup
        setupObligation(obligation, 100);
        oracle.setPrice(1e36 - 1);
        deal(address(loanToken), address(this), 1);

        // Test
        Seizure[] memory seizures = new Seizure[](1);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 1, seized: 0});
        morphoV2.liquidate(obligation, seizures, borrower, data);

        assertEq(recordedSeizures.length, 1, "seizures length");
        assertEq(recordedSeizures[0].repaid, 1, "repaid obligations");
        assertEq(recordedSeizures[0].seized, 1, "seized assets");
        assertEq(recordedBorrower, borrower, "borrower");
        assertEq(recordedLiquidator, address(this), "liquidator");
        assertEq(recordedData, data, "data");
    }

    // Check that if there is bad debt it is possible to seize all assets.
    function testLiquidateAllWhenBadDebt() public {
        Oracle oracle2 = new Oracle();
        obligation.collaterals[1].oracle = address(oracle2);
        id = toId(obligation);

        setupMaxObligationWithCollaterals(obligation, 100, 100);
        uint256 price = 1e36 * 1e18 / LIQUIDATION_INCENTIVE_FACTOR * 95 / 100;
        uint256 price2 = 1e36 * 1e18 / LIQUIDATION_INCENTIVE_FACTOR;
        oracle.setPrice(price);
        oracle2.setPrice(price2);
        deal(address(loanToken), address(this), 100e18);

        Seizure[] memory seizures = new Seizure[](2);
        seizures[0] = Seizure({collateralIndex: 0, repaid: 0, seized: 100});
        seizures[1] = Seizure({collateralIndex: 1, repaid: 0, seized: 100});

        morphoV2.liquidate(obligation, seizures, borrower, "");
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
