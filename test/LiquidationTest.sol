// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {MAX_LIF, WAD, ORACLE_PRICE_SCALE, TIME_TO_MAX_LIF} from "../src/libraries/ConstantsLib.sol";
import {Obligation, Collateral} from "../src/interfaces/IMorphoV2.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";

contract LiquidationTest is BaseTest {
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    Obligation internal obligation;
    bytes20 internal id;

    uint256 internal recordedRepaidUnits;
    bytes internal recordedData;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.85e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);
        obligation.rcfThreshold = 0;

        id = toId(obligation);

        deal(address(loanToken), address(this), type(uint256).max);
    }

    function testLiquidateInvalidCollateralIndex() public {
        uint256 units = 100e18;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(1e36 - 1);

        vm.expectRevert(stdError.indexOOBError);
        morphoV2.liquidate(obligation, 2, 0, 0, borrower, "");
    }

    function testLiquidateInactiveCollateralIndex(uint256 units) public {
        units = bound(units, 10, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(0);

        assertEq(morphoV2.collateralOf(id, borrower, 1), 0);

        vm.expectRevert();
        morphoV2.liquidate(obligation, 1, 0, 1, borrower, "");

        vm.expectRevert();
        morphoV2.liquidate(obligation, 1, 1, 0, borrower, "");

        uint256 collatBefore = morphoV2.collateralOf(id, borrower, 0);
        morphoV2.liquidate(obligation, 1, 0, 0, borrower, "");
        assertEq(morphoV2.debtOf(id, borrower), 0);
        assertEq(morphoV2.collateralOf(id, borrower, 0), collatBefore);
        assertEq(morphoV2.collateralOf(id, borrower, 1), 0);
    }

    function testLiquidateHealthyPreMaturity(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        liquidationOraclePrice = bound(liquidationOraclePrice, ORACLE_PRICE_SCALE, 10 * ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);

        vm.expectRevert("position is not liquidatable");
        morphoV2.liquidate(obligation, 0, 0, 0, borrower, "");
    }

    function testLiquidateUnhealthyPreMaturity(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        liquidationOraclePrice = bound(liquidationOraclePrice, 0, ORACLE_PRICE_SCALE - 1);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);

        morphoV2.liquidate(obligation, 0, 0, 0, borrower, "");
    }

    function testLiquidateHealthyPostMaturity(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        liquidationOraclePrice = bound(liquidationOraclePrice, ORACLE_PRICE_SCALE, 10 * ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);
        obligation.maturity = block.timestamp - 1;

        morphoV2.liquidate(obligation, 0, 0, 0, borrower, "");
    }

    function testLiquidateUnhealthyPostMaturity(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        liquidationOraclePrice = bound(liquidationOraclePrice, 0, ORACLE_PRICE_SCALE - 1);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        obligation.maturity = block.timestamp - 1;
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);

        morphoV2.liquidate(obligation, 0, 0, 0, borrower, "");
    }

    function testLiquidateInconsistentInput(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        vm.expectRevert("INCONSISTENT_INPUT");
        morphoV2.liquidate(obligation, 0, 1, 1, borrower, "");
    }

    function testLiquidateObligationUnitsInput(uint256 units, uint256 repaid, uint256 liquidationOraclePrice) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, units);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceUp(units), ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, 0);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF); // Warp to post-maturity to bypass recovery close factor.

        (uint256 seizedAssets, uint256 repaidUnits) = morphoV2.liquidate(obligation, 0, 0, repaid, borrower, "");

        assertEq(repaidUnits, repaid, "repaid units");
        assertEq(
            seizedAssets,
            repaid.mulDivDown(ORACLE_PRICE_SCALE, liquidationOraclePrice).mulDivDown(MAX_LIF, WAD),
            "seized assets"
        );

        assertEq(morphoV2.debtOf(id, borrower), units - repaidUnits);
        assertEq(morphoV2.collateralOf(id, borrower, 0), initialCollateral - seizedAssets);
    }

    function testLiquidateCollateralInput(uint256 units, uint256 seized, uint256 liquidationOraclePrice) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceUp(units), ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, 0);
        seized = bound(
            seized,
            0,
            UtilsLib.min(
                units.mulDivDown(ORACLE_PRICE_SCALE, liquidationOraclePrice).mulDivDown(MAX_LIF, WAD), initialCollateral
            )
        );
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF); // Warp to post-maturity to bypass recovery close factor.

        (uint256 seizedAssets, uint256 repaidUnits) = morphoV2.liquidate(obligation, 0, seized, 0, borrower, "");

        assertEq(
            repaidUnits,
            seized.mulDivUp(WAD, MAX_LIF).mulDivUp(liquidationOraclePrice, ORACLE_PRICE_SCALE),
            "repaid units"
        );
        assertEq(seizedAssets, seized, "seized assets");

        assertEq(morphoV2.debtOf(id, borrower), units - repaidUnits, "debt");
        assertEq(morphoV2.collateralOf(id, borrower, 0), initialCollateral - seizedAssets, "collateral");
    }

    function testLiquidateCallback(uint256 units, uint256 repaid, uint256 liquidationOraclePrice, bytes memory data)
        public
    {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, units);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceUp(units), ORACLE_PRICE_SCALE);
        vm.assume(data.length > 0);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF); // Warp to post-maturity to bypass recovery close factor.

        morphoV2.liquidate(obligation, 0, 0, repaid, borrower, data);

        assertEq(recordedRepaidUnits, repaid, "repaid units");
        assertEq(recordedData, data, "data");
    }

    function testCannotRepayMoreThanDebt(uint256 units, uint256 repaid, uint256 liquidationOraclePrice) public {
        units = bound(units, 10, MAX_TEST_AMOUNT - 1);
        repaid = bound(repaid, units + 1, MAX_TEST_AMOUNT);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceUp(units), ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF); // Warp to post-maturity to bypass recovery close factor.
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);

        vm.expectRevert(stdError.arithmeticError);
        morphoV2.liquidate(obligation, 0, 0, repaid, borrower, "");
    }

    function testCannotSeizeMoreThanCollateral(uint256 units, uint256 seized, uint256 liquidationOraclePrice) public {
        units = bound(units, 10, MAX_TEST_AMOUNT - 1);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceUp(units), ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF); // Warp to post-maturity to bypass recovery close factor.
        seized = bound(seized, morphoV2.collateralOf(id, borrower, 0) + 1, MAX_TEST_AMOUNT * 2);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);

        vm.expectRevert(stdError.arithmeticError);
        morphoV2.liquidate(obligation, 0, seized, 0, borrower, "");
    }

    // Test bad debt.

    function testRealizeOnlyBadDebt(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 10, MAX_TEST_AMOUNT); // if the amount is too small, no bad debt is created.
        liquidationOraclePrice = bound(liquidationOraclePrice, 1, badDebtPriceDown());
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);
        uint256 expectedBadDebt = _badDebt();

        morphoV2.liquidate(obligation, 0, 0, 0, borrower, "");

        assertEq(morphoV2.debtOf(id, borrower), units - expectedBadDebt, "debt");
        assertEq(morphoV2.totalUnits(id), units - expectedBadDebt, "total units");
        assertEq(morphoV2.totalShares(id), units, "total shares");
    }

    function testLiquidateWithBadDebtSeizedInput(uint256 units, uint256 seized, uint256 liquidationOraclePrice) public {
        units = bound(units, 10, MAX_TEST_AMOUNT); // if the amount is too small, no bad debt is created.
        liquidationOraclePrice = bound(liquidationOraclePrice, 1, badDebtPriceDown());
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);

        uint256 debtAfterBadDebt = units - _badDebt();
        uint256 maxRepaid = _maxRepaid();
        uint256 maxSeized = maxRepaid.mulDivDown(ORACLE_PRICE_SCALE, liquidationOraclePrice).mulDivDown(MAX_LIF, WAD);
        // guarantee the recovery close factor is not violated
        seized = bound(seized, 0, maxSeized);

        uint256 maxSeizedByDebt =
            debtAfterBadDebt.mulDivDown(ORACLE_PRICE_SCALE, liquidationOraclePrice).mulDivDown(MAX_LIF, WAD);
        // guarantee repaid <= debtAfterBadDebt
        seized = bound(seized, 0, maxSeizedByDebt);

        (, uint256 repaid) = morphoV2.liquidate(obligation, 0, seized, 0, borrower, "");

        assertEq(morphoV2.debtOf(id, borrower), debtAfterBadDebt - repaid, "debt");
        assertEq(morphoV2.totalUnits(id), debtAfterBadDebt, "total units");
        assertEq(morphoV2.totalShares(id), units, "total shares");
    }

    function testLiquidateWithBadDebtRepaidInput(uint256 units, uint256 repaid, uint256 liquidationOraclePrice) public {
        units = bound(units, 10, MAX_TEST_AMOUNT); // if the amount is too small, no bad debt is created.
        liquidationOraclePrice = bound(liquidationOraclePrice, 1, badDebtPriceDown());
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);
        uint256 debtAfterBadDebt = units - _badDebt();
        uint256 maxRepaid = _maxRepaid();
        repaid = bound(repaid, 0, maxRepaid);

        morphoV2.liquidate(obligation, 0, 0, repaid, borrower, "");

        assertEq(morphoV2.debtOf(id, borrower), debtAfterBadDebt - repaid, "debt");
        assertEq(morphoV2.totalUnits(id), debtAfterBadDebt, "total units");
        assertEq(morphoV2.totalShares(id), units, "total shares");
    }

    // Check that if there is bad debt it is possible to repay all debt.
    function testLiquidateWithBadDebtRepayAll(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 10, MAX_TEST_AMOUNT);
        liquidationOraclePrice = bound(liquidationOraclePrice, 1, badDebtPriceDown());

        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);

        uint256 debtAfterBadDebt = units - _badDebt();

        uint256 collatAmount = morphoV2.collateralOf(id, borrower, 0);
        uint256 maxRepaid = _maxRepaid();
        uint256 maxCollateralRepayable =
            collatAmount.mulDivDown(liquidationOraclePrice, ORACLE_PRICE_SCALE).mulDivDown(WAD, MAX_LIF);

        uint256 repaidAmount = UtilsLib.min(UtilsLib.min(debtAfterBadDebt, maxRepaid), maxCollateralRepayable); // capped
        // by the debt, the recovery close factor and the collateral amount

        morphoV2.liquidate(obligation, 0, 0, repaidAmount, borrower, "");

        assertEq(morphoV2.debtOf(id, borrower), debtAfterBadDebt - repaidAmount, "all remaining debt repaid");
    }

    // post maturity liquidation.

    function testLiquidatePostMaturityFullLIF(
        uint256 units,
        uint256 repaid,
        uint256 delay,
        uint256 liquidationOraclePrice
    ) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, units);
        delay = bound(delay, 0, 100 weeks);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceUp(units), ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF + delay);

        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, 0);

        morphoV2.liquidate(obligation, 0, 0, repaid, borrower, "");

        assertEq(morphoV2.debtOf(id, borrower), units - repaid, "debt");
        assertEq(
            morphoV2.collateralOf(id, borrower, 0),
            initialCollateral - repaid.mulDivDown(ORACLE_PRICE_SCALE, liquidationOraclePrice).mulDivDown(MAX_LIF, WAD),
            "collateral"
        );
    }

    function testLiquidatePostMaturityPartialLIF(
        uint256 units,
        uint256 repaid,
        uint256 delay,
        uint256 liquidationOraclePrice
    ) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, units);
        delay = bound(delay, 1, TIME_TO_MAX_LIF);
        liquidationOraclePrice = bound(liquidationOraclePrice, ORACLE_PRICE_SCALE, 10 * ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);
        vm.warp(obligation.maturity + delay);

        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, 0);

        morphoV2.liquidate(obligation, 0, 0, repaid, borrower, "");

        uint256 lif = WAD + (MAX_LIF - WAD) * delay / TIME_TO_MAX_LIF;

        assertEq(morphoV2.debtOf(id, borrower), units - repaid, "debt");
        assertEq(
            morphoV2.collateralOf(id, borrower, 0),
            initialCollateral - repaid.mulDivDown(ORACLE_PRICE_SCALE, liquidationOraclePrice).mulDivDown(lif, WAD),
            "collateral"
        );
    }

    // recovery close factor

    function testMaxRepaid(uint256 units, uint256 liquidationOraclePrice, uint256 repaid) public {
        units = bound(units, 100, MAX_TEST_AMOUNT);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceUp(units), ORACLE_PRICE_SCALE - 1);
        _setupUnhealthy(units, liquidationOraclePrice);
        uint256 maxRepay = _maxRepaid();
        assertLt(maxRepay, units, "max repaid > units");

        repaid = bound(repaid, maxRepay + 1, units);
        vm.expectRevert("recovery close factor conditions violated");
        morphoV2.liquidate(obligation, 0, 0, repaid, borrower, "");

        repaid = bound(repaid, 0, maxRepay);
        morphoV2.liquidate(obligation, 0, 0, repaid, borrower, "");
    }

    function testMaxRepaidMeansRecovery(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 100, MAX_TEST_AMOUNT);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceUp(units), ORACLE_PRICE_SCALE - 1);
        _setupUnhealthy(units, liquidationOraclePrice);
        uint256 maxRepay = _maxRepaid();
        assertLt(maxRepay, units, "max repaid > units");

        morphoV2.liquidate(obligation, 0, 0, maxRepay, borrower, "");

        uint256 remainingCollateral = morphoV2.collateralOf(id, borrower, 0);
        uint256 remainingDebt = morphoV2.debtOf(id, borrower);
        uint256 newMaxDebt = remainingCollateral.mulDivDown(liquidationOraclePrice, ORACLE_PRICE_SCALE)
            .mulDivDown(obligation.collaterals[0].lltv, WAD);
        // After max repayment the position should be almost healthy (within rounding tolerance).
        assertGt(
            remainingDebt,
            newMaxDebt.zeroFloorSub(3),
            "position should be approximately just unhealthy after max repayment"
        );
    }

    /// @dev When rcfThreshold > remaining debt after max repayment, full liquidation is allowed pre-maturity.
    function testRcfThresholdAllowsFullLiquidation(uint256 units, uint256 liquidationOraclePrice, uint256 rcfThreshold)
        public
    {
        units = bound(units, 100, MAX_TEST_AMOUNT);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceUp(units), ORACLE_PRICE_SCALE - 1);

        // Compute remaining debt after max repayment from the input parameters.
        uint256 lltv = obligation.collaterals[0].lltv;
        uint256 collatAmount = units.mulDivUp(WAD, lltv);
        uint256 maxRepaid = _maxRepaid();
        uint256 remainingRepayable = collatAmount.mulDivDown(liquidationOraclePrice, ORACLE_PRICE_SCALE)
            .mulDivDown(WAD, MAX_LIF).zeroFloorSub(maxRepaid);
        obligation.rcfThreshold = bound(rcfThreshold, remainingRepayable + 1, type(uint256).max);

        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);

        // Full liquidation should succeed because remaining debt < rcfThreshold.
        morphoV2.liquidate(obligation, 0, 0, units, borrower, "");
        assertEq(morphoV2.debtOf(toId(obligation), borrower), 0, "debt should be zero");
    }

    /// @dev When rcfThreshold <= remaining debt after max repayment, recovery close factor is enforced.
    function testRcfThresholdEnforcesRecoveryCloseFactor(
        uint256 units,
        uint256 liquidationOraclePrice,
        uint256 rcfThreshold
    ) public {
        units = bound(units, 100, MAX_TEST_AMOUNT);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceUp(units), ORACLE_PRICE_SCALE - 1);

        // Compute remaining debt after max repayment from the input parameters.
        uint256 lltv = obligation.collaterals[0].lltv;
        uint256 collatAmount = units.mulDivUp(WAD, lltv);
        uint256 maxRepaid = _maxRepaid();
        uint256 remainingRepayable = collatAmount.mulDivDown(liquidationOraclePrice, ORACLE_PRICE_SCALE)
            .mulDivDown(WAD, MAX_LIF).zeroFloorSub(maxRepaid);
        obligation.rcfThreshold = bound(rcfThreshold, 0, remainingRepayable);

        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);

        // Full liquidation should revert because remaining debt >= rcfThreshold.
        vm.expectRevert("recovery close factor conditions violated");
        morphoV2.liquidate(obligation, 0, 0, units, borrower, "");
    }

    /// @dev Recovery close factor applies at exact maturity but not one second after.
    function testRecoveryCloseFactorMaturityBoundary(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 100, MAX_TEST_AMOUNT);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceUp(units), ORACLE_PRICE_SCALE - 1);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);
        assertLt(_maxRepaid(), units, "max repaid > units");

        // At exact maturity: recovery close factor applies.
        vm.warp(obligation.maturity);
        vm.expectRevert("recovery close factor conditions violated");
        morphoV2.liquidate(obligation, 0, 0, units, borrower, "");

        // One second later: recovery close factor no longer applies.
        vm.warp(obligation.maturity + 1);
        morphoV2.liquidate(obligation, 0, 0, units, borrower, "");
        assertEq(morphoV2.debtOf(id, borrower), 0);
    }

    /// @dev Recovery close factor with two collaterals contributing to maxDebt.
    /// Drops price of the lower-lltv collateral to make position unhealthy, then liquidates it.
    function testRecoveryCloseFactorMultipleCollaterals(uint256 units) public {
        units = bound(units, 100, MAX_TEST_AMOUNT);

        uint256 lltv0 = obligation.collaterals[0].lltv;
        uint256 lltv1 = obligation.collaterals[1].lltv;

        // Deposit enough for each collateral so position is healthy at par.
        uint256 collatPerToken = units.mulDivUp(WAD, lltv0 + lltv1) + 1;
        for (uint256 i = 0; i < 2; i++) {
            address token = obligation.collaterals[i].token;
            deal(token, address(this), collatPerToken);
            ERC20(token).approve(address(morphoV2), collatPerToken);
            morphoV2.supplyCollateral(obligation, i, collatPerToken, borrower);
        }

        setupObligation(obligation, units);

        // Liquidate the collateral with lower lltv (bigger recovery spread).
        uint256 liqIdx = lltv0 <= lltv1 ? 0 : 1;
        uint256 otherIdx = 1 - liqIdx;

        // Drop price of liquidated collateral. 0.9e36 is above critical price for lltv=0.75 (0.8625e36).
        uint256 droppedPrice = 0.9e36;
        Oracle(obligation.collaterals[liqIdx].oracle).setPrice(droppedPrice);

        uint256 liqCollat = morphoV2.collateralOf(id, borrower, liqIdx);
        uint256 otherCollat = morphoV2.collateralOf(id, borrower, otherIdx);
        uint256 maxDebtOverestimated = liqCollat.mulDivUp(droppedPrice, ORACLE_PRICE_SCALE).mulDivUp(MAX_LIF, WAD)
            + otherCollat.mulDivUp(MAX_LIF, WAD);

        uint256 maxR = units.zeroFloorSub(maxDebtOverestimated)
            .mulDivDown(WAD, WAD - MAX_LIF.mulDivUp(obligation.collaterals[liqIdx].lltv, WAD));

        morphoV2.liquidate(obligation, liqIdx, 0, maxR, borrower, "");
    }

    // gas tests

    /// forge-config: default.isolate = true
    function testGasLiquidateMultipleCollaterals() public {
        uint256 units = 1000e18;
        uint256 collateralAmount = units.mulDivUp(WAD, obligation.collaterals[0].lltv);

        // Supply both collaterals.
        for (uint256 i = 0; i < 2; i++) {
            address token = obligation.collaterals[i].token;
            deal(token, address(this), collateralAmount);
            ERC20(token).approve(address(morphoV2), collateralAmount);
            morphoV2.supplyCollateral(obligation, i, collateralAmount, borrower);
        }

        setupObligation(obligation, units);

        // Make position liquidatable.
        oracle1.setPrice(0.5e36);
        oracle2.setPrice(0.5e36);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF);

        uint256 repay = units / 2;

        uint256 snapshot = vm.snapshotState();

        // Multicall with 1 liquidation.
        bytes[] memory calls1 = new bytes[](1);
        calls1[0] = abi.encodeCall(morphoV2.liquidate, (obligation, 0, 0, repay, borrower, ""));
        uint256 gasBefore1 = gasleft();
        morphoV2.multicall(calls1);
        uint256 gas1 = gasBefore1 - gasleft();
        vm.revertToState(snapshot);

        // Multicall with 2 liquidations.
        bytes[] memory calls2 = new bytes[](2);
        calls2[0] = abi.encodeCall(morphoV2.liquidate, (obligation, 0, 0, repay, borrower, ""));
        calls2[1] = abi.encodeCall(morphoV2.liquidate, (obligation, 1, 0, repay, borrower, ""));
        uint256 gasBefore2 = gasleft();
        morphoV2.multicall(calls2);
        uint256 gas2 = gasBefore2 - gasleft();

        emit log_named_uint("Gas 1st seizure (cold)", gas1);
        emit log_named_uint("Gas 2nd seizure (warm)", gas2 - gas1);
    }

    // helpers.

    /// @dev Bad debt as computed in liquidate
    function _badDebt() internal view returns (uint256) {
        uint256 badDebt = morphoV2.debtOf(id, borrower);
        uint256 bitmap = morphoV2.activatedCollaterals(id, borrower);
        while (bitmap != 0) {
            uint256 i = UtilsLib.msb(bitmap);
            Collateral memory _collateral = obligation.collaterals[i];
            uint256 price = IOracle(_collateral.oracle).price();
            uint256 _collateralOf = morphoV2.collateralOf(id, borrower, i);
            badDebt = badDebt.zeroFloorSub(_collateralOf.mulDivDown(WAD, MAX_LIF).mulDivDown(price, ORACLE_PRICE_SCALE));
            bitmap ^= (1 << i);
        }
        return badDebt;
    }

    /// @dev A price below which the position will create bad debt.
    function badDebtPriceDown() internal view returns (uint256) {
        return obligation.collaterals[0].lltv * MAX_LIF;
    }

    /// @dev A price above which the position will not create bad debt.
    function badDebtPriceUp(uint256 units) internal view returns (uint256) {
        uint256 lltv = obligation.collaterals[0].lltv;
        uint256 collateral = units.mulDivUp(WAD, lltv);
        return units.mulDivUp(ORACLE_PRICE_SCALE, collateral.mulDivDown(WAD, MAX_LIF));
    }

    function _maxRepaid() internal view returns (uint256) {
        uint256 lltv = obligation.collaterals[0].lltv;
        uint256 oraclePrice = IOracle(obligation.collaterals[0].oracle).price();
        uint256 debtAfterBadDebt = morphoV2.debtOf(id, borrower) - _badDebt();
        uint256 maxDebtOverestimated = morphoV2.collateralOf(id, borrower, 0).mulDivUp(WAD, lltv)
            .mulDivUp(oraclePrice, ORACLE_PRICE_SCALE).mulDivUp(MAX_LIF, WAD);
        return debtAfterBadDebt.zeroFloorSub(maxDebtOverestimated).mulDivDown(WAD, WAD - MAX_LIF.mulDivUp(lltv, WAD));
    }

    function _setupUnhealthy(uint256 units, uint256 liquidationOraclePrice)
        internal
        returns (uint256 collatAmount, uint256 _maxDebt)
    {
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        collatAmount = morphoV2.collateralOf(id, borrower, 0);
        Oracle(obligation.collaterals[0].oracle).setPrice(liquidationOraclePrice);
        _maxDebt = collatAmount.mulDivDown(liquidationOraclePrice, ORACLE_PRICE_SCALE)
            .mulDivDown(obligation.collaterals[0].lltv, WAD);
    }

    function onLiquidate(Obligation memory, uint256, uint256, uint256 _repaidUnits, address, bytes memory data) public {
        recordedRepaidUnits = _repaidUnits;
        recordedData = data;
    }
}
