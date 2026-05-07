// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {
    WAD,
    ORACLE_PRICE_SCALE,
    TIME_TO_MAX_LIF,
    LLTV_8,
    LIQUIDATION_CURSOR_LOW,
    CALLBACK_SUCCESS
} from "../src/libraries/ConstantsLib.sol";
import {IMidnight, Obligation, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {IdLib} from "../src/libraries/IdLib.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";

// Collateral = units / lltv (up to ~1.33x for lltv=0.75).
// To keep collateral within uint128, we cap amounts at type(uint128).max / 2.
uint256 constant MAX_UNITS = MAX_TEST_AMOUNT / 2;

contract LiquidationTest is BaseTest {
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    Obligation internal obligation;
    bytes32 internal id;

    uint256 internal recordedRepaidUnits;
    bytes internal recordedData;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: 0.86e18,
                    maxLif: maxLif(0.86e18, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        obligation.collateralParams = sortCollateralParams(obligation.collateralParams);
        obligation.rcfThreshold = 0;

        id = toId(obligation);

        deal(address(loanToken), address(this), type(uint256).max);
    }

    function testLiquidateInvalidCollateralIndex() public {
        uint256 units = 100e18;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(1e36 - 1);

        vm.expectRevert(stdError.indexOOBError);
        midnight.liquidate(obligation, 2, 0, 0, borrower, address(this), address(0), "");
    }

    function testLiquidateInactiveCollateralIndex(uint256 units) public {
        units = bound(units, 10, MAX_UNITS);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(0);

        assertEq(midnight.collateral(id, borrower, 1), 0);

        vm.expectRevert();
        midnight.liquidate(obligation, 1, 0, 1, borrower, address(this), address(0), "");

        vm.expectRevert();
        midnight.liquidate(obligation, 1, 1, 0, borrower, address(this), address(0), "");

        uint256 collatBefore = midnight.collateral(id, borrower, 0);
        midnight.liquidate(obligation, 1, 0, 0, borrower, address(this), address(0), "");
        assertEq(midnight.debtOf(id, borrower), 0);
        assertEq(midnight.collateral(id, borrower, 0), collatBefore);
        assertEq(midnight.collateral(id, borrower, 1), 0);
    }

    function testLiquidateHealthyPreMaturity(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 1, MAX_UNITS);
        liquidationOraclePrice = bound(liquidationOraclePrice, ORACLE_PRICE_SCALE, 10 * ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);

        vm.expectRevert(IMidnight.NotLiquidatable.selector);
        midnight.liquidate(obligation, 0, 0, 0, borrower, address(this), address(0), "");
    }

    function testLiquidateUnhealthyPreMaturity(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 1, MAX_UNITS);
        liquidationOraclePrice = bound(liquidationOraclePrice, 0, ORACLE_PRICE_SCALE - 1);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);

        midnight.liquidate(obligation, 0, 0, 0, borrower, address(this), address(0), "");
    }

    function testLiquidateHealthyPostMaturity(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 1, MAX_UNITS);
        liquidationOraclePrice = bound(liquidationOraclePrice, ORACLE_PRICE_SCALE, 10 * ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);
        vm.warp(obligation.maturity + 1);

        midnight.liquidate(obligation, 0, 0, 0, borrower, address(this), address(0), "");
    }

    function testLiquidateUnhealthyPostMaturity(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 1, MAX_UNITS);
        liquidationOraclePrice = bound(liquidationOraclePrice, 0, ORACLE_PRICE_SCALE - 1);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        vm.warp(obligation.maturity + 1);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);

        midnight.liquidate(obligation, 0, 0, 0, borrower, address(this), address(0), "");
    }

    function testLiquidateInconsistentInput(uint256 units) public {
        units = bound(units, 1, MAX_UNITS);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        vm.expectRevert(IMidnight.InconsistentInput.selector);
        midnight.liquidate(obligation, 0, 1, 1, borrower, address(this), address(0), "");
    }

    function testLiquidateUnitsInput(uint256 units, uint256 repaid, uint256 liquidationOraclePrice) public {
        units = bound(units, 1, MAX_UNITS);
        repaid = bound(repaid, 0, units);
        liquidationOraclePrice = bound(liquidationOraclePrice, fullRepaymentPrice(units), ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        uint256 initialCollateral = midnight.collateral(id, borrower, 0);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF); // Warp to post-maturity to bypass recovery close factor.

        (uint256 seizedAssets, uint256 repaidUnits) =
            midnight.liquidate(obligation, 0, 0, repaid, borrower, address(this), address(0), "");

        assertEq(repaidUnits, repaid, "repaid units");
        assertEq(
            seizedAssets,
            repaid.mulDivDown(obligation.collateralParams[0].maxLif, WAD)
                .mulDivDown(ORACLE_PRICE_SCALE, liquidationOraclePrice),
            "seized assets"
        );

        assertEq(midnight.debtOf(id, borrower), units - repaidUnits);
        assertEq(midnight.collateral(id, borrower, 0), initialCollateral - seizedAssets);
    }

    function testLiquidateCollateralInput(uint256 units, uint256 seized, uint256 liquidationOraclePrice) public {
        units = bound(units, 1, MAX_UNITS);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceDown(units) + 1, ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        uint256 initialCollateral = midnight.collateral(id, borrower, 0);
        seized = bound(
            seized,
            0,
            UtilsLib.min(
                units.mulDivDown(obligation.collateralParams[0].maxLif, WAD)
                    .mulDivDown(ORACLE_PRICE_SCALE, liquidationOraclePrice),
                initialCollateral
            )
        );
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF); // Warp to post-maturity to bypass recovery close factor.

        (uint256 seizedAssets, uint256 repaidUnits) =
            midnight.liquidate(obligation, 0, seized, 0, borrower, address(this), address(0), "");

        assertEq(
            repaidUnits,
            seized.mulDivUp(liquidationOraclePrice, ORACLE_PRICE_SCALE)
                .mulDivUp(WAD, obligation.collateralParams[0].maxLif),
            "repaid units"
        );
        assertEq(seizedAssets, seized, "seized assets");

        assertEq(midnight.debtOf(id, borrower), units - repaidUnits, "debt");
        assertEq(midnight.collateral(id, borrower, 0), initialCollateral - seizedAssets, "collateral");
    }

    function testLiquidateCallback(
        uint256 units,
        uint256 repaid,
        uint256 liquidationOraclePrice,
        bytes memory data,
        address caller
    ) public {
        units = bound(units, 1, MAX_UNITS);
        repaid = bound(repaid, 0, units);
        liquidationOraclePrice = bound(liquidationOraclePrice, fullRepaymentPrice(units), ORACLE_PRICE_SCALE);
        vm.assume(data.length > 0);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF); // Warp to post-maturity to bypass recovery close factor.

        vm.prank(caller);
        midnight.liquidate(obligation, 0, 0, repaid, borrower, address(this), address(this), data);

        assertEq(recordedRepaidUnits, repaid, "repaid units");
        assertEq(recordedData, data, "data");
    }

    function testCannotRepayMoreThanDebt(uint256 units, uint256 repaid, uint256 liquidationOraclePrice) public {
        units = bound(units, 10, MAX_UNITS - 1);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF); // Warp to post-maturity to bypass recovery close factor.

        uint256 _maxLif = obligation.collateralParams[0].maxLif;
        uint256 collateral = midnight.collateral(id, borrower, 0);

        // Price must be high enough that seized assets for (units + 1) don't exceed available collateral.
        uint256 minPrice = (units + 1).mulDivUp(_maxLif, WAD).mulDivUp(ORACLE_PRICE_SCALE, collateral);
        liquidationOraclePrice = bound(liquidationOraclePrice, minPrice, ORACLE_PRICE_SCALE);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);

        // Bound repaid above debt but within collateral capacity so the "repay too much" check is reached.
        uint256 maxRepaid = collateral.mulDivDown(liquidationOraclePrice, ORACLE_PRICE_SCALE).mulDivDown(WAD, _maxLif);
        repaid = bound(repaid, units + 1, max(maxRepaid, units + 1));

        vm.expectRevert(stdError.arithmeticError);
        midnight.liquidate(obligation, 0, 0, repaid, borrower, address(this), address(0), "");
    }

    function testCannotSeizeMoreThanCollateral(uint256 units, uint256 seized, uint256 liquidationOraclePrice) public {
        units = bound(units, 10, MAX_UNITS);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceDown(units) + 1, ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF); // Warp to post-maturity to bypass recovery close factor.
        seized = bound(seized, midnight.collateral(id, borrower, 0) + 1, MAX_TEST_AMOUNT);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);

        vm.expectRevert(stdError.arithmeticError);
        midnight.liquidate(obligation, 0, seized, 0, borrower, address(this), address(0), "");
    }

    function testBadDebtPriceDownGivesBadDebt(uint256 units) public {
        units = bound(units, 10, MAX_UNITS);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(badDebtPriceDown(units));

        assertGt(_badDebt(), 0, "should have bad debt at badDebtPriceDown");
    }

    function testBadDebtPriceDownIsMaximal(uint256 units) public {
        units = bound(units, 10, MAX_UNITS);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(badDebtPriceDown(units) + 1);

        assertEq(_badDebt(), 0, "should have no bad debt at badDebtPriceDown");
    }

    // Test bad debt.

    function testRealizeOnlyBadDebt(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 10, MAX_UNITS); // if the amount is too small, no bad debt is created.
        liquidationOraclePrice = bound(liquidationOraclePrice, 1, badDebtPriceDown(units));
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);
        uint256 expectedBadDebt = _badDebt();

        midnight.liquidate(obligation, 0, 0, 0, borrower, address(this), address(0), "");

        assertEq(midnight.debtOf(id, borrower), units - expectedBadDebt, "debt");
        assertEq(midnight.totalUnits(id), units - expectedBadDebt, "total units");
        assertEq(midnight.creditOf(id, lender), units, "lender units");
        midnight.updatePosition(obligation, lender);
        assertApproxEqAbs(midnight.creditOf(id, lender), units - expectedBadDebt, 1, "lender units after slashing");
    }

    function testLiquidateEmitsLossFactor(uint256 units) public {
        units = bound(units, 10, MAX_UNITS);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(badDebtPriceDown(units));

        uint256 expectedBadDebt = _badDebt();
        uint128 oldTotalUnits = midnight.totalUnits(id).toUint128();
        uint256 previousLossFactor = midnight.lossFactor(id);
        uint256 expectedLossFactor = expectedBadDebt == 0
            ? previousLossFactor
            : type(uint128).max
                - (type(uint128).max - previousLossFactor).mulDivDown(oldTotalUnits - expectedBadDebt, oldTotalUnits);

        vm.expectEmit(true, true, true, true);
        emit EventsLib.Liquidate(
            address(this),
            id,
            obligation.collateralParams[0].token,
            0,
            0,
            borrower,
            expectedBadDebt,
            expectedLossFactor,
            address(this),
            address(this)
        );
        midnight.liquidate(obligation, 0, 0, 0, borrower, address(this), address(0), "");
    }

    function testSlashNonFull(uint256 units) public {
        units = bound(units, 10, MAX_UNITS);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(badDebtPriceDown(units));

        midnight.liquidate(obligation, 0, 0, 0, borrower, address(this), address(0), "");

        uint256 lossFactor = midnight.lossFactor(id);
        uint256 expectedCredit = units.mulDivDown(type(uint128).max - lossFactor, type(uint128).max);

        vm.expectEmit(true, true, false, true);
        emit EventsLib.UpdatePosition(id, lender, units - expectedCredit, 0, 0);
        midnight.updatePosition(obligation, lender);

        assertEq(midnight.creditOf(id, lender), expectedCredit, "credit");
        assertEq(midnight.lastLossFactor(id, lender), lossFactor, "last loss factor");
    }

    function testLiquidateWithBadDebtSeizedInput(uint256 units, uint256 seized, uint256 liquidationOraclePrice) public {
        units = bound(units, 10, MAX_UNITS); // if the amount is too small, no bad debt is created.
        liquidationOraclePrice = bound(liquidationOraclePrice, 1, badDebtPriceDown(units));
        collateralize(obligation, borrower, units);
        seized = bound(seized, 0, midnight.collateral(id, borrower, 0));
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);
        uint256 debtAfterBadDebt = units - _badDebt();

        (, uint256 repaid) = midnight.liquidate(obligation, 0, seized, 0, borrower, address(this), address(0), "");

        assertEq(midnight.debtOf(id, borrower), debtAfterBadDebt - repaid, "debt");
        assertEq(midnight.totalUnits(id), debtAfterBadDebt, "total units");
        assertEq(midnight.creditOf(id, lender), units, "lender units");
        midnight.updatePosition(obligation, lender);
        assertApproxEqAbs(midnight.creditOf(id, lender), debtAfterBadDebt, 1, "lender units after slashing");
    }

    function testLiquidateWithBadDebtRepaidInput(uint256 units, uint256 repaid, uint256 liquidationOraclePrice) public {
        units = bound(units, 10, MAX_UNITS); // if the amount is too small, no bad debt is created.
        liquidationOraclePrice = bound(liquidationOraclePrice, 1, badDebtPriceDown(units));
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);
        uint256 debtAfterBadDebt = units - _badDebt();
        uint256 maxRepaid = _maxRepaid(units, debtAfterBadDebt, liquidationOraclePrice);
        uint256 lif0 = obligation.collateralParams[0].maxLif;
        uint256 maxRepaidFromCollat = midnight.collateral(id, borrower, 0)
            .mulDivDown(liquidationOraclePrice, ORACLE_PRICE_SCALE).mulDivDown(WAD, lif0);
        repaid = bound(repaid, 0, UtilsLib.min(UtilsLib.min(maxRepaid, debtAfterBadDebt), maxRepaidFromCollat));

        midnight.liquidate(obligation, 0, 0, repaid, borrower, address(this), address(0), "");

        assertEq(midnight.debtOf(id, borrower), debtAfterBadDebt - repaid, "debt");
        assertEq(midnight.totalUnits(id), debtAfterBadDebt, "total units");
        assertEq(midnight.creditOf(id, lender), units, "lender units");
        midnight.updatePosition(obligation, lender);
        assertApproxEqAbs(midnight.creditOf(id, lender), debtAfterBadDebt, 1, "lender units after slashing");
    }

    // Check that if there is bad debt it is possible to seize almost all collateral.
    function testLiquidateWithBadDebtSeizeMax(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 10, MAX_UNITS);
        liquidationOraclePrice = bound(liquidationOraclePrice, 1, badDebtPriceDown(units));
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);

        midnight.liquidate(
            obligation, 0, midnight.collateral(id, borrower, 0), 0, borrower, address(this), address(0), ""
        );

        assertApproxEqAbs(midnight.debtOf(id, borrower), 0, 1e3, "almost all remaining debt repaid");
        assertApproxEqAbs(
            midnight.collateral(id, borrower, 0).mulDivDown(liquidationOraclePrice, ORACLE_PRICE_SCALE),
            0,
            1e3,
            "almost all collateral seized"
        );
    }

    // post maturity liquidation.

    function testLiquidatePostMaturityFullLIF(
        uint256 units,
        uint256 repaid,
        uint256 delay,
        uint256 liquidationOraclePrice
    ) public {
        units = bound(units, 1, MAX_UNITS);
        repaid = bound(repaid, 0, units);
        delay = bound(delay, 0, 100 weeks);

        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        liquidationOraclePrice = bound(liquidationOraclePrice, fullRepaymentPrice(units), ORACLE_PRICE_SCALE);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF + delay);

        uint256 initialCollateral = midnight.collateral(id, borrower, 0);

        midnight.liquidate(obligation, 0, 0, repaid, borrower, address(this), address(0), "");

        assertEq(midnight.debtOf(id, borrower), units - repaid, "debt");
        assertEq(
            midnight.collateral(id, borrower, 0),
            initialCollateral
                - repaid.mulDivDown(obligation.collateralParams[0].maxLif, WAD)
                    .mulDivDown(ORACLE_PRICE_SCALE, liquidationOraclePrice),
            "collateral"
        );
    }

    function testLiquidatePostMaturityPartialLIF(
        uint256 units,
        uint256 repaid,
        uint256 delay,
        uint256 liquidationOraclePrice
    ) public {
        units = bound(units, 1, MAX_UNITS);
        repaid = bound(repaid, 0, units);
        delay = bound(delay, 1, TIME_TO_MAX_LIF);
        liquidationOraclePrice = bound(liquidationOraclePrice, ORACLE_PRICE_SCALE, 10 * ORACLE_PRICE_SCALE);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);
        vm.warp(obligation.maturity + delay);

        uint256 initialCollateral = midnight.collateral(id, borrower, 0);

        midnight.liquidate(obligation, 0, 0, repaid, borrower, address(this), address(0), "");

        uint256 lif = WAD + (obligation.collateralParams[0].maxLif - WAD) * delay / TIME_TO_MAX_LIF;

        assertEq(midnight.debtOf(id, borrower), units - repaid, "debt");
        assertEq(
            midnight.collateral(id, borrower, 0),
            initialCollateral - repaid.mulDivDown(lif, WAD).mulDivDown(ORACLE_PRICE_SCALE, liquidationOraclePrice),
            "collateral"
        );
    }

    // recovery close factor

    function testMaxRepaid(uint256 units, uint256 liquidationOraclePrice, uint256 repaid) public {
        units = bound(units, 100, MAX_UNITS);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceDown(units) + 1, ORACLE_PRICE_SCALE - 1);

        _setupUnhealthy(units, liquidationOraclePrice);

        uint256 maxR = _maxRepaid(units, units, liquidationOraclePrice);

        repaid = bound(repaid, maxR + 1, max(units, maxR + 1));
        vm.expectRevert(IMidnight.RecoveryCloseFactorConditionsViolated.selector);
        midnight.liquidate(obligation, 0, 0, repaid, borrower, address(this), address(0), "");

        repaid = bound(repaid, 0, min(maxR, units));
        midnight.liquidate(obligation, 0, 0, repaid, borrower, address(this), address(0), "");
    }

    function testMaxRepaidMeansRecovery(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 100, MAX_UNITS);
        liquidationOraclePrice = bound(liquidationOraclePrice, fullRepaymentPrice(units), ORACLE_PRICE_SCALE - 1);

        _setupUnhealthy(units, liquidationOraclePrice);

        uint256 maxR = _maxRepaid(units, units, liquidationOraclePrice);

        midnight.liquidate(obligation, 0, 0, min(maxR, units), borrower, address(this), address(0), "");

        uint256 remainingCollateral = midnight.collateral(id, borrower, 0);
        uint256 remainingDebt = midnight.debtOf(id, borrower);
        uint256 newMaxDebt = remainingCollateral.mulDivDown(liquidationOraclePrice, ORACLE_PRICE_SCALE)
            .mulDivDown(obligation.collateralParams[0].lltv, WAD);
        // After max repayment the position should be just healthy or almost healthy (within rounding tolerance).
        assertLe(remainingDebt, newMaxDebt + 3, "position should be approximately just healthy after max repayment");
    }

    /// @dev When rcfThreshold > remaining debt after max repayment, full liquidation is allowed pre-maturity.
    function testRcfThresholdAllowsFullLiquidation(uint256 units, uint256 liquidationOraclePrice, uint256 rcfThreshold)
        public
    {
        units = bound(units, 100, MAX_UNITS);
        liquidationOraclePrice = bound(liquidationOraclePrice, fullRepaymentPrice(units), ORACLE_PRICE_SCALE - 1);

        // Compute remaining debt after max repayment from the input parameters.
        uint256 lltv = obligation.collateralParams[0].lltv;
        uint256 collatAmount = units.mulDivUp(WAD, lltv);
        uint256 maxRepaid = _maxRepaid(units, units, liquidationOraclePrice);
        uint256 lif0 = obligation.collateralParams[0].maxLif;
        uint256 remainingRepayable = collatAmount.mulDivDown(liquidationOraclePrice, ORACLE_PRICE_SCALE)
            .mulDivDown(WAD, lif0).zeroFloorSub(maxRepaid);
        obligation.rcfThreshold = bound(rcfThreshold, remainingRepayable + 1, type(uint256).max);

        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);

        // Full liquidation should succeed because remaining debt < rcfThreshold.
        midnight.liquidate(obligation, 0, 0, units, borrower, address(this), address(0), "");
        assertEq(midnight.debtOf(toId(obligation), borrower), 0, "debt should be zero");
    }

    /// @dev When rcfThreshold <= remaining debt after max repayment, recovery close factor is enforced.
    function testRcfThresholdEnforcesRecoveryCloseFactor(
        uint256 units,
        uint256 liquidationOraclePrice,
        uint256 rcfThreshold
    ) public {
        units = bound(units, 100, MAX_UNITS);
        liquidationOraclePrice = bound(liquidationOraclePrice, badDebtPriceDown(units) + 1, ORACLE_PRICE_SCALE - 1);

        // Compute remaining debt after max repayment from the input parameters.
        uint256 lltv = obligation.collateralParams[0].lltv;
        uint256 collatAmount = units.mulDivUp(WAD, lltv);
        uint256 maxRepaid = _maxRepaid(units, units, liquidationOraclePrice);
        vm.assume(maxRepaid < units); // needed because of the round up.
        uint256 remainingRepayable = collatAmount.mulDivDown(liquidationOraclePrice, ORACLE_PRICE_SCALE)
            .mulDivDown(WAD, obligation.collateralParams[0].maxLif).zeroFloorSub(maxRepaid);
        obligation.rcfThreshold = bound(rcfThreshold, 0, remainingRepayable);

        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);

        // Full liquidation should revert because remaining debt >= rcfThreshold.
        vm.expectRevert(IMidnight.RecoveryCloseFactorConditionsViolated.selector);
        midnight.liquidate(obligation, 0, 0, units, borrower, address(this), address(0), "");
    }

    /// @dev Recovery close factor applies at exact maturity but not one second after.
    function testRecoveryCloseFactorMaturityBoundary(uint256 units, uint256 liquidationOraclePrice) public {
        units = bound(units, 100, MAX_UNITS);
        liquidationOraclePrice = bound(liquidationOraclePrice, fullRepaymentPrice(units), ORACLE_PRICE_SCALE - 1);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);
        uint256 maxRepaid = _maxRepaid(units, units, liquidationOraclePrice);

        // At exact maturity: recovery close factor applies.
        if (maxRepaid < units) {
            vm.warp(obligation.maturity);
            vm.expectRevert(IMidnight.RecoveryCloseFactorConditionsViolated.selector);
            midnight.liquidate(obligation, 0, 0, units, borrower, address(this), address(0), "");
        }

        // One second later: recovery close factor no longer applies.
        vm.warp(obligation.maturity + 1);
        midnight.liquidate(obligation, 0, 0, units, borrower, address(this), address(0), "");
        assertEq(midnight.debtOf(id, borrower), 0);
    }

    /// @dev With RCF deactivated, liquidation can always end by fully repaying debt or fully seizing collateral.
    function testLiquidateFullyRepayOrFullySeizeWhenRcfDeactivated(
        uint256 units,
        uint256 collateral1,
        uint256 collateral2
    ) public {
        collateral1 = bound(collateral1, 1, MAX_UNITS);
        collateral2 = bound(collateral2, 1, MAX_UNITS);

        // Deactivate RCF.
        obligation.rcfThreshold = type(uint256).max;
        id = toId(obligation);

        // Price is 1 initially, assume liquidatable but no bad debt.
        uint256 maxDebt = collateral1.mulDivDown(obligation.collateralParams[0].lltv, WAD)
            + collateral2.mulDivDown(obligation.collateralParams[1].lltv, WAD);
        uint256 repayableDebt = collateral1.mulDivDown(WAD, obligation.collateralParams[0].maxLif)
            + collateral2.mulDivDown(WAD, obligation.collateralParams[1].maxLif);
        units = bound(units, maxDebt, repayableDebt);
        vm.assume(units > maxDebt);

        // Write debt into Position storage.
        // Layout: slot 0 = credit | pendingFee, slot 1 = lastLossFactor | lastAccrual,
        // slot 2 = debt | collateralBitmap.
        // Debt is in the lower 128 bits of slot 2.
        uint256 mappingSlot = 0;
        bytes32 intermediateSlot = keccak256(abi.encode(id, mappingSlot));
        bytes32 borrowerSlot = keccak256(abi.encode(borrower, intermediateSlot));
        vm.store(address(midnight), bytes32(uint256(borrowerSlot) + 2), bytes32(units));

        assertEq(midnight.debtOf(id, borrower), units, "debt");

        // Collateralize with both collateralParams.

        vm.prank(borrower);

        midnight.setIsAuthorized(borrower, address(this), true);

        deal(obligation.collateralParams[0].token, address(this), collateral1);
        midnight.supplyCollateral(obligation, 0, collateral1, borrower);

        deal(obligation.collateralParams[1].token, address(this), collateral2);
        midnight.supplyCollateral(obligation, 1, collateral2, borrower);

        // Check that the position has no bad debt.
        // If it had bad debt, this can be taken into account separately.
        assertEq(_badDebt(), 0, "no bad debt");

        uint256 collateralNeededToRepayAll = units.mulDivDown(obligation.collateralParams[0].maxLif, WAD);
        if (collateralNeededToRepayAll <= collateral1) {
            midnight.liquidate(obligation, 0, 0, units, borrower, address(this), address(0), "");
        } else {
            midnight.liquidate(obligation, 0, collateral1, 0, borrower, address(this), address(0), "");
        }

        uint256 debtAfter = midnight.debtOf(id, borrower);
        uint256 collateralAfter = midnight.collateral(id, borrower, 0);
        assertTrue(debtAfter == 0 || collateralAfter == 0, "either debt repaid or collateral seized");
    }

    /// @dev Recovery close factor with two collateralParams contributing to maxDebt. Drops price of the lower-lltv
    /// collateral to make position unhealthy, then liquidates it.
    function testRecoveryCloseFactorMultipleCollaterals(uint256 units) public {
        units = bound(units, 100, MAX_UNITS);

        uint256 lltv0 = obligation.collateralParams[0].lltv;
        uint256 lltv1 = obligation.collateralParams[1].lltv;

        vm.prank(borrower);

        midnight.setIsAuthorized(borrower, address(this), true);

        // Deposit enough for each collateral so position is healthy at par.
        uint256 collatPerToken = units.mulDivUp(WAD, lltv0 + lltv1) + 1;
        for (uint256 i = 0; i < 2; i++) {
            address token = obligation.collateralParams[i].token;
            deal(token, address(this), collatPerToken);
            midnight.supplyCollateral(obligation, i, collatPerToken, borrower);
        }

        setupObligation(obligation, units);

        // Liquidate the collateral with lower lltv (bigger recovery spread).
        uint256 liqIdx = lltv0 <= lltv1 ? 0 : 1;
        uint256 otherIdx = 1 - liqIdx;

        // Drop price of liquidated collateral. 0.9e36 is above critical price for lltv=0.75 (0.8625e36).
        uint256 droppedPrice = 0.9e36;
        Oracle(obligation.collateralParams[liqIdx].oracle).setPrice(droppedPrice);

        uint256 liqCollat = midnight.collateral(id, borrower, liqIdx);
        uint256 otherCollat = midnight.collateral(id, borrower, otherIdx);
        uint256 _maxDebt = liqCollat.mulDivDown(droppedPrice, ORACLE_PRICE_SCALE)
            .mulDivDown(obligation.collateralParams[liqIdx].lltv, WAD)
        + otherCollat.mulDivDown(obligation.collateralParams[otherIdx].lltv, WAD);

        uint256 maxR = (units - _maxDebt)
        .mulDivUp(
            WAD,
            WAD - obligation.collateralParams[liqIdx].maxLif.mulDivUp(obligation.collateralParams[liqIdx].lltv, WAD)
        );

        midnight.liquidate(obligation, liqIdx, 0, maxR, borrower, address(this), address(0), "");
    }

    // gas tests

    /// forge-config: default.isolate = true
    function testGasLiquidateMultipleCollaterals() public {
        uint256 units = 1000e18;
        uint256 collateralAmount = units.mulDivUp(WAD, obligation.collateralParams[0].lltv);

        vm.prank(borrower);

        midnight.setIsAuthorized(borrower, address(this), true);

        // Supply both collateralParams.
        for (uint256 i = 0; i < 2; i++) {
            address token = obligation.collateralParams[i].token;
            deal(token, address(this), collateralAmount);
            midnight.supplyCollateral(obligation, i, collateralAmount, borrower);
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
        calls1[0] =
            abi.encodeCall(midnight.liquidate, (obligation, 0, 0, repay, borrower, address(this), address(0), ""));
        uint256 gasBefore1 = gasleft();
        midnight.multicall(calls1);
        uint256 gas1 = gasBefore1 - gasleft();
        vm.revertToState(snapshot);

        // Multicall with 2 liquidations.
        bytes[] memory calls2 = new bytes[](2);
        calls2[0] =
            abi.encodeCall(midnight.liquidate, (obligation, 0, 0, repay, borrower, address(this), address(0), ""));
        calls2[1] =
            abi.encodeCall(midnight.liquidate, (obligation, 1, 0, repay, borrower, address(this), address(0), ""));
        uint256 gasBefore2 = gasleft();
        midnight.multicall(calls2);
        uint256 gas2 = gasBefore2 - gasleft();

        emit log_named_uint("Gas 1st seizure (cold)", gas1);
        emit log_named_uint("Gas 2nd seizure (warm)", gas2 - gas1);
    }

    // slash tests.

    function testSlashNoBadDebt(uint256 units) public {
        units = bound(units, 1, MAX_UNITS);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        uint256 creditBefore = midnight.creditOf(id, lender);

        midnight.updatePosition(obligation, lender);

        assertEq(midnight.creditOf(id, lender), creditBefore, "credit unchanged");
    }

    function testSlashNoCredit(uint256 units) public {
        units = bound(units, 10, MAX_UNITS);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        Oracle(obligation.collateralParams[0].oracle).setPrice(badDebtPriceDown(units));
        midnight.liquidate(obligation, 0, 0, 0, borrower, address(this), address(0), "");

        assertEq(midnight.creditOf(id, borrower), 0, "no credit before");
        uint256 debtBefore = midnight.debtOf(id, borrower);
        uint128 oblLossFactor = midnight.lossFactor(id);
        assertGt(oblLossFactor, midnight.lastLossFactor(id, borrower), "last loss factor stale before");

        midnight.updatePosition(obligation, borrower);

        assertEq(midnight.creditOf(id, borrower), 0, "no credit after");
        assertEq(midnight.debtOf(id, borrower), debtBefore, "debt unchanged");
        assertEq(midnight.lastLossFactor(id, borrower), oblLossFactor, "last loss factor synced");
    }

    function testSlashAlreadySynced(uint256 units) public {
        units = bound(units, 10, MAX_UNITS);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        Oracle(obligation.collateralParams[0].oracle).setPrice(badDebtPriceDown(units));
        midnight.liquidate(obligation, 0, 0, 0, borrower, address(this), address(0), "");

        uint256 creditBeforeSlash = midnight.creditOf(id, lender);
        midnight.updatePosition(obligation, lender);
        uint256 creditAfterFirstSlash = midnight.creditOf(id, lender);
        uint128 lastLossFactorAfterFirstSlash = midnight.lastLossFactor(id, lender);
        assertLt(creditAfterFirstSlash, creditBeforeSlash, "first slash reduced credit");

        midnight.updatePosition(obligation, lender);

        assertEq(midnight.creditOf(id, lender), creditAfterFirstSlash, "credit unchanged");
        assertEq(midnight.lastLossFactor(id, lender), lastLossFactorAfterFirstSlash, "last loss factor unchanged");
    }

    // full bad debt test.

    function testFullBadDebtWithdrawCollateral(uint256 units) public {
        units = bound(units, 10, MAX_UNITS);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        Oracle(obligation.collateralParams[0].oracle).setPrice(0);
        midnight.liquidate(obligation, 0, 0, 0, borrower, address(this), address(0), "");

        assertEq(midnight.debtOf(id, borrower), 0, "debt");
        assertEq(midnight.totalUnits(id), 0, "total units");
        uint128 _lossFactor = midnight.lossFactor(id);
        assertEq(_lossFactor, type(uint128).max, "loss factor");
        midnight.updatePosition(obligation, lender);
        assertEq(midnight.creditOf(id, lender), 0, "credit after slashing");

        // withdrawCollateral still works
        uint256 collateral = midnight.collateral(id, borrower, 0);
        assertGt(collateral, 0, "has collateral");
        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, address(this), true);
        midnight.withdrawCollateral(obligation, 0, collateral, borrower, borrower);
        assertEq(midnight.collateral(id, borrower, 0), 0, "collateral withdrawn");
    }

    // helpers.

    /// @dev Bad debt as computed in liquidate
    function _badDebt() internal view returns (uint256) {
        uint256 badDebt = midnight.debtOf(id, borrower);
        uint128 collateralBitmap = midnight.collateralBitmap(id, borrower);
        while (collateralBitmap != 0) {
            uint256 i = UtilsLib.msb(collateralBitmap);
            CollateralParams memory _collateral = obligation.collateralParams[i];
            uint256 price = IOracle(_collateral.oracle).price();
            badDebt = badDebt.zeroFloorSub(
                midnight.collateral(id, borrower, i).mulDivUp(price, ORACLE_PRICE_SCALE)
                    .mulDivUp(WAD, _collateral.maxLif)
            );
            require(i < 128, "i is too large");
            // forge-lint: disable-next-line(unsafe-typecast) as i < 128 is checked above.
            collateralBitmap ^= uint128(1 << i);
        }
        return badDebt;
    }

    /// @dev A price below which the position will create bad debt.
    function badDebtPriceDown(uint256 units) internal view returns (uint256) {
        uint256 lltv = obligation.collateralParams[0].lltv;
        uint256 maxLif = obligation.collateralParams[0].maxLif;
        uint256 collateral = units.mulDivUp(WAD, lltv);
        return (units - 1).mulDivDown(maxLif, WAD).mulDivDown(ORACLE_PRICE_SCALE, collateral);
    }

    /// @dev A price above which full repayment does not exceed available collateral.
    function fullRepaymentPrice(uint256 units) internal view returns (uint256) {
        uint256 lltv = obligation.collateralParams[0].lltv;
        uint256 maxLif = obligation.collateralParams[0].maxLif;
        uint256 collateral = units.mulDivUp(WAD, lltv);
        return units.mulDivUp(maxLif, WAD).mulDivUp(ORACLE_PRICE_SCALE, collateral);
    }

    function _maxRepaid(uint256 units, uint256 debt, uint256 oraclePrice) internal view returns (uint256) {
        uint256 lltv = obligation.collateralParams[0].lltv;
        uint256 collatAmount = units.mulDivUp(WAD, lltv);
        uint256 _maxDebt = collatAmount.mulDivDown(oraclePrice, ORACLE_PRICE_SCALE).mulDivDown(lltv, WAD);
        return (debt - _maxDebt).mulDivUp(WAD, WAD - obligation.collateralParams[0].maxLif.mulDivUp(lltv, WAD));
    }

    function _setupUnhealthy(uint256 units, uint256 liquidationOraclePrice)
        internal
        returns (uint256 collatAmount, uint256 _maxDebt)
    {
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        collatAmount = midnight.collateral(id, borrower, 0);
        Oracle(obligation.collateralParams[0].oracle).setPrice(liquidationOraclePrice);
        _maxDebt = collatAmount.mulDivDown(liquidationOraclePrice, ORACLE_PRICE_SCALE)
            .mulDivDown(obligation.collateralParams[0].lltv, WAD);
    }

    /// @dev Tests that non-zero liquidation works pre-maturity when LLTV = WAD (1e18). Before the fix, this reverted
    /// with a division-by-zero in the recovery close factor check.
    function testLiquidatePreMaturityLltvWad(uint256 units) public {
        units = bound(units, 2, MAX_UNITS);

        // Override obligation to use LLTV_8 = WAD on collateral 0.
        delete obligation.collateralParams;
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: LLTV_8,
                    maxLif: maxLif(LLTV_8, LIQUIDATION_CURSOR_LOW),
                    oracle: address(oracle1)
                })
            );
        id = toId(obligation);

        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        // Drop price so position is unhealthy.
        Oracle(obligation.collateralParams[0].oracle).setPrice(ORACLE_PRICE_SCALE / 2);

        uint256 debtBefore = midnight.debtOf(id, borrower);
        // Non-zero seizedAssets exercises the recovery close factor path.
        midnight.liquidate(obligation, 0, 1, 0, borrower, address(this), address(0), "");
        assertLt(midnight.debtOf(id, borrower), debtBefore, "debt should decrease after liquidation");
    }

    function testLiquidateNoDebtReverts() public {
        midnight.touchObligation(obligation);
        vm.expectRevert(IMidnight.NotLiquidatable.selector);
        midnight.liquidate(obligation, 0, 0, 0, borrower, address(this), address(0), "");
    }

    function onLiquidate(
        bytes32 _id,
        Obligation memory _obligation,
        uint256,
        uint256,
        uint256 _repaidUnits,
        address,
        bytes memory data
    ) public returns (bytes32) {
        require(_id == IdLib.toId(_obligation, block.chainid, msg.sender), "wrong id");
        recordedRepaidUnits = _repaidUnits;
        recordedData = data;
        return CALLBACK_SUCCESS;
    }
}
