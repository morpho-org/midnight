// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {MAX_LIF, WAD, ORACLE_PRICE_SCALE, TIME_TO_MAX_LIF} from "../src/libraries/ConstantsLib.sol";
import {Obligation, Collateral, Seizure} from "../src/interfaces/IMorphoV2.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";

contract LiquidationTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;

    Seizure[] internal recordedSeizures;
    address internal recordedBorrower;
    address internal recordedLiquidator;
    bytes internal recordedData;

    Seizure[] internal seizures;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = toId(obligation);
    }

    function testLiquidateHealthyPreMaturity(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        vm.expectRevert("position is not liquidatable");
        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateUnhealthyPreMaturity(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(0);

        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateHealthyPostMaturity(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        obligation.maturity = block.timestamp - 1;

        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateUnhealthyPostMaturity(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        obligation.maturity = block.timestamp - 1;
        Oracle(obligation.collaterals[0].oracle).setPrice(0);

        morphoV2.liquidate(obligation, new Seizure[](0), borrower, "");
    }

    function testLiquidateNoOp(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(0);

        morphoV2.liquidate(obligation, seizures, borrower, "");
    }

    function testLiquidateInconsistentInput(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(0);
        seizures.push(Seizure({collateralIndex: 0, repaid: 1, seized: 1}));

        vm.expectRevert("INCONSISTENT_INPUT");
        morphoV2.liquidate(obligation, seizures, borrower, "");
    }

    function testLiquidateObligationUnitsInput(uint256 units, uint256 repaid) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, units);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token);
        Oracle(obligation.collaterals[0].oracle).setPrice(1e36 - 1);
        deal(address(loanToken), address(this), repaid);
        seizures.push(Seizure({collateralIndex: 0, repaid: repaid, seized: 0}));

        Seizure[] memory actualSeizures = morphoV2.liquidate(obligation, seizures, borrower, "");

        assertEq(actualSeizures.length, 1, "seizures length");
        assertEq(actualSeizures[0].collateralIndex, 0, "collateral index");
        assertEq(actualSeizures[0].repaid, repaid, "repaid units");
        assertEq(
            actualSeizures[0].seized,
            repaid.mulDivDown(ORACLE_PRICE_SCALE, 1e36 - 1).mulDivDown(MAX_LIF, WAD),
            "seized assets"
        );

        assertEq(morphoV2.debtOf(id, borrower), units - actualSeizures[0].repaid);
        assertEq(
            morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token),
            initialCollateral - actualSeizures[0].seized
        );
        assertEq(loanToken.balanceOf(address(this)), 0);
    }

    function testLiquidateCollateralInput(uint256 units, uint256 seized) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token);
        seized = bound(seized, 0, units.mulDivDown(MAX_LIF, WAD));
        Oracle(obligation.collaterals[0].oracle).setPrice(1e36 - 1);
        uint256 repaid = seized.mulDivUp(WAD, MAX_LIF).mulDivUp(1e36 - 1, ORACLE_PRICE_SCALE);
        deal(address(loanToken), address(this), repaid);
        seizures.push(Seizure({collateralIndex: 0, repaid: 0, seized: seized}));

        Seizure[] memory actualSeizures = morphoV2.liquidate(obligation, seizures, borrower, "");

        assertEq(actualSeizures.length, 1, "seizures length");
        assertEq(actualSeizures[0].collateralIndex, 0, "collateral index");
        assertEq(
            actualSeizures[0].repaid,
            seized.mulDivUp(WAD, MAX_LIF).mulDivUp(1e36 - 1, ORACLE_PRICE_SCALE),
            "repaid units"
        );
        assertEq(actualSeizures[0].seized, seized, "seized assets");

        assertEq(loanToken.balanceOf(address(this)), 0, "loan token balance");
        assertEq(morphoV2.debtOf(id, borrower), units - actualSeizures[0].repaid, "debt");
        assertEq(
            morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token),
            initialCollateral - actualSeizures[0].seized,
            "collateral"
        );
    }

    function testLiquidateCallback(uint256 units, uint256 repaid, bytes memory data) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, units);
        vm.assume(data.length > 0);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(1e36 - 1);
        deal(address(loanToken), address(this), units);
        seizures.push(Seizure({collateralIndex: 0, repaid: repaid, seized: 0}));

        morphoV2.liquidate(obligation, seizures, borrower, data);

        assertEq(recordedSeizures.length, 1, "seizures length");
        assertEq(recordedSeizures[0].repaid, repaid, "repaid units");
        assertEq(
            recordedSeizures[0].seized,
            repaid.mulDivDown(ORACLE_PRICE_SCALE, 1e36 - 1).mulDivDown(MAX_LIF, WAD),
            "seized assets"
        );
        assertEq(recordedBorrower, borrower, "borrower");
        assertEq(recordedLiquidator, address(this), "liquidator");
        assertEq(recordedData, data, "data");
    }

    function testLiquidateTwoCollateralsSeizedInput(
        uint256 units,
        uint256 secondCollateral,
        uint256 seized1,
        uint256 seized2,
        uint256 oraclePrice1,
        uint256 oraclePrice2
    ) public {
        units = bound(units, 10, MAX_TEST_AMOUNT);
        oraclePrice1 = bound(oraclePrice1, 1, 0.9e36);
        oraclePrice2 = bound(oraclePrice2, 1, 0.9e36);
        uint256 totalCollateral = units.mulDivUp(WAD, 0.75e18) + 1; // because we round twice in the health check
        secondCollateral = bound(secondCollateral, 0, totalCollateral);
        seized1 = bound(seized1, 0, (totalCollateral - secondCollateral) / 2);
        seized2 = bound(seized2, 0, secondCollateral / 2);
        deal(obligation.collaterals[0].token, address(this), totalCollateral - secondCollateral);
        morphoV2.supplyCollateral(
            obligation, obligation.collaterals[0].token, totalCollateral - secondCollateral, borrower
        );
        deal(obligation.collaterals[1].token, address(this), secondCollateral);
        morphoV2.supplyCollateral(obligation, obligation.collaterals[1].token, secondCollateral, borrower);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(oraclePrice1);
        Oracle(obligation.collaterals[1].oracle).setPrice(oraclePrice2);
        seizures.push(Seizure({collateralIndex: 0, repaid: 0, seized: seized1}));
        seizures.push(Seizure({collateralIndex: 1, repaid: 0, seized: seized2}));
        deal(address(loanToken), address(this), units); // over-approx.

        morphoV2.liquidate(obligation, seizures, borrower, "");
    }

    function testLiquidateTwoCollateralsRepaidInput(
        uint256 units,
        uint256 secondCollateral,
        uint256 repaid1,
        uint256 repaid2,
        uint256 oraclePrice1,
        uint256 oraclePrice2
    ) public {
        units = bound(units, 10, MAX_TEST_AMOUNT);
        oraclePrice1 = bound(oraclePrice1, 1, 0.9e36);
        oraclePrice2 = bound(oraclePrice2, 1, 0.9e36);
        uint256 totalCollateral = units.mulDivUp(WAD, 0.75e18) + 1; // because we round twice in the health check
        secondCollateral = bound(secondCollateral, 0, totalCollateral);
        repaid1 = bound(
            repaid1,
            0,
            ((totalCollateral - secondCollateral) / 2).mulDivDown(WAD, MAX_LIF)
                .mulDivDown(oraclePrice1, ORACLE_PRICE_SCALE)
        );
        repaid2 = bound(
            repaid2, 0, (secondCollateral / 2).mulDivDown(WAD, MAX_LIF).mulDivDown(oraclePrice2, ORACLE_PRICE_SCALE)
        );
        deal(obligation.collaterals[0].token, address(this), totalCollateral - secondCollateral);
        morphoV2.supplyCollateral(
            obligation, obligation.collaterals[0].token, totalCollateral - secondCollateral, borrower
        );
        deal(obligation.collaterals[1].token, address(this), secondCollateral);
        morphoV2.supplyCollateral(obligation, obligation.collaterals[1].token, secondCollateral, borrower);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(oraclePrice1);
        Oracle(obligation.collaterals[1].oracle).setPrice(oraclePrice2);
        seizures.push(Seizure({collateralIndex: 0, repaid: repaid1, seized: 0}));
        seizures.push(Seizure({collateralIndex: 1, repaid: repaid2, seized: 0}));
        deal(address(loanToken), address(this), units); // over-approx.

        morphoV2.liquidate(obligation, seizures, borrower, "");
    }

    function testCannotRepayMoreThanDebt(uint256 units, uint256 repaid) public {
        units = bound(units, 10, MAX_TEST_AMOUNT - 1);
        repaid = bound(repaid, units + 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(1e36 - 1);
        deal(address(loanToken), address(this), units);
        deal(address(loanToken), address(this), units);
        seizures.push(Seizure({collateralIndex: 0, repaid: repaid, seized: 0}));

        vm.expectRevert(stdError.arithmeticError);
        morphoV2.liquidate(obligation, seizures, borrower, "");
    }

    function testCannotSeizeMoreThanCollateral(uint256 units, uint256 seized) public {
        units = bound(units, 10, MAX_TEST_AMOUNT - 1);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        seized = bound(
            seized, morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token) + 1, MAX_TEST_AMOUNT * 2
        );
        Oracle(obligation.collaterals[0].oracle).setPrice(1e36 - 1);
        deal(address(loanToken), address(this), units);
        deal(address(loanToken), address(this), units);
        seizures.push(Seizure({collateralIndex: 0, repaid: 0, seized: seized}));

        vm.expectRevert(stdError.arithmeticError);
        morphoV2.liquidate(obligation, seizures, borrower, "");
    }

    // Test bad debt.

    function testRealizeOnlyBadDebt(uint256 units) public {
        units = bound(units, 10, MAX_TEST_AMOUNT); // if the amount is too small, no bad debt is created.
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        uint256 oraclePrice = 0.5e36;
        Oracle(obligation.collaterals[0].oracle).setPrice(oraclePrice); // TODO fuzz
        uint256 repayable = morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token).mulDivUp(WAD, MAX_LIF)
            .mulDivUp(oraclePrice, ORACLE_PRICE_SCALE);
        uint256 expectedBadDebt = units - repayable;

        morphoV2.liquidate(obligation, seizures, borrower, ""); // empty seizures.

        assertEq(morphoV2.debtOf(id, borrower), units - expectedBadDebt, "debt");
        assertEq(morphoV2.totalUnits(id), units - expectedBadDebt, "total units");
        assertEq(morphoV2.totalShares(id), units, "total shares");
    }

    function testLiquidateWithBadDebtSeizedInput(uint256 units, uint256 seized) public {
        units = bound(units, 10, MAX_TEST_AMOUNT); // if the amount is too small, no bad debt is created.
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token);
        seized = bound(seized, 0, initialCollateral);
        uint256 oraclePrice = 0.5e36;
        Oracle(obligation.collaterals[0].oracle).setPrice(oraclePrice);
        uint256 repayable = morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token).mulDivUp(WAD, MAX_LIF)
            .mulDivUp(oraclePrice, ORACLE_PRICE_SCALE);
        uint256 expectedBadDebt = units - repayable;
        uint256 repaid = seized.mulDivUp(WAD, MAX_LIF).mulDivUp(oraclePrice, ORACLE_PRICE_SCALE);

        deal(address(loanToken), address(this), units); // over-approx.
        seizures.push(Seizure({collateralIndex: 0, repaid: 0, seized: seized}));

        morphoV2.liquidate(obligation, seizures, borrower, "");

        assertEq(morphoV2.debtOf(id, borrower), units - expectedBadDebt - repaid, "debt");
        assertEq(morphoV2.totalUnits(id), units - expectedBadDebt, "total units");
        assertEq(morphoV2.totalShares(id), units, "total shares");
    }

    function testLiquidateWithBadDebtRepaidInput(uint256 units, uint256 repaid) public {
        units = bound(units, 10, MAX_TEST_AMOUNT); // if the amount is too small, no bad debt is created.
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(0.5e36);
        uint256 repayableDebt = morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token)
            .mulDivUp(WAD, MAX_LIF).mulDivUp(0.5e36, ORACLE_PRICE_SCALE);
        repaid = bound(repaid, 0, repayableDebt - 1); // TODO fix - 1.
        uint256 expectedBadDebt = units - repayableDebt;
        deal(address(loanToken), address(this), repaid);
        seizures.push(Seizure({collateralIndex: 0, repaid: repaid, seized: 0}));

        morphoV2.liquidate(obligation, seizures, borrower, "");

        assertEq(morphoV2.debtOf(id, borrower), units - repaid - expectedBadDebt, "debt");
        assertEq(morphoV2.totalUnits(id), units - expectedBadDebt, "total units");
        assertEq(morphoV2.totalShares(id), units, "total shares");
    }

    // Check that if there is bad debt it is possible to seize all assets.
    function testLiquidateWithBadDebtSeizeAll(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token);
        Oracle(obligation.collaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE / 2); // TODO fuzz
        deal(address(loanToken), address(this), units); // not needed.
        seizures.push(Seizure({collateralIndex: 0, repaid: 0, seized: initialCollateral}));

        morphoV2.liquidate(obligation, seizures, borrower, "");

        assertEq(morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token), 0);
    }

    // post maturity liquidation.

    function testLiquidatePostMaturityFullLIF(uint256 units, uint256 repaid, uint256 delay) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, units);
        delay = bound(delay, 0, 100 weeks);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF + delay);
        deal(address(loanToken), address(this), units);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token);
        seizures.push(Seizure({collateralIndex: 0, repaid: repaid, seized: 0}));

        morphoV2.liquidate(obligation, seizures, borrower, "");

        assertEq(morphoV2.debtOf(id, borrower), units - repaid, "debt");
        assertEq(
            morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token),
            initialCollateral - repaid.mulDivDown(MAX_LIF, WAD),
            "collateral"
        );
    }

    function testLiquidatePostMaturityPartialLIF(uint256 units, uint256 repaid, uint256 delay) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, units);
        delay = bound(delay, 1, TIME_TO_MAX_LIF);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        vm.warp(obligation.maturity + delay);
        deal(address(loanToken), address(this), units);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token);
        seizures.push(Seizure({collateralIndex: 0, repaid: repaid, seized: 0}));

        morphoV2.liquidate(obligation, seizures, borrower, "");

        uint256 lif = WAD + (MAX_LIF - WAD) * delay / TIME_TO_MAX_LIF;

        assertEq(morphoV2.debtOf(id, borrower), units - repaid, "debt");
        assertEq(
            morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token),
            initialCollateral - repaid.mulDivDown(lif, WAD),
            "collateral"
        );
    }

    // helpers.

    function onLiquidate(Seizure[] memory _seizures, address borrower, address liquidator, bytes memory data) public {
        for (uint256 i = 0; i < _seizures.length; i++) {
            recordedSeizures.push(_seizures[i]);
        }
        recordedBorrower = borrower;
        recordedLiquidator = liquidator;
        recordedData = data;
    }
}
