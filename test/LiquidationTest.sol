// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {MAX_LIF, WAD, ORACLE_PRICE_SCALE, TIME_TO_MAX_LIF} from "../src/libraries/ConstantsLib.sol";
import {Obligation, Collateral, Offer} from "../src/interfaces/IMorphoV2.sol";
import {TICK_RANGE} from "../src/libraries/TickLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";
import {console} from "../lib/forge-std/src/console.sol";
contract LiquidationTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;

    uint256 internal recordedRepaidAssets;
    bytes internal recordedData;

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

    function testLiquidateInvalidCollateralIndex() public {
        vm.expectRevert(stdError.indexOOBError);
        morphoV2.liquidate(obligation, 2, 0, 0, borrower, "");
    }

    function testLiquidateHealthyPreMaturity(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        vm.expectRevert("position is not liquidatable");
        morphoV2.liquidate(obligation, 0, 0, 0, borrower, "");
    }

    function testLiquidateUnhealthyPreMaturity(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(0);

        morphoV2.liquidate(obligation, 0, 0, 0, borrower, "");
    }

    function testLiquidateHealthyPostMaturity(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        obligation.maturity = block.timestamp - 1;

        morphoV2.liquidate(obligation, 0, 0, 0, borrower, "");
    }

    function testLiquidateUnhealthyPostMaturity(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        obligation.maturity = block.timestamp - 1;
        Oracle(obligation.collaterals[0].oracle).setPrice(0);

        morphoV2.liquidate(obligation, 0, 0, 0, borrower, "");
    }

    function testLiquidateNoOp(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(0);

        morphoV2.liquidate(obligation, 0, 0, 0, borrower, "");
    }

    function testLiquidateInconsistentInput(uint256 units) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(0);

        vm.expectRevert("INCONSISTENT_INPUT");
        morphoV2.liquidate(obligation, 0, 1, 1, borrower, "");
    }

    function testLiquidateObligationUnitsInput(uint256 units, uint256 repaid) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        repaid = bound(repaid, 0, units);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token);
        Oracle(obligation.collaterals[0].oracle).setPrice(1e36 - 1);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF); // Warp to post-maturity to bypass recovery close factor.
        deal(address(loanToken), address(this), repaid);

        (uint256 repaidAssets, uint256 seizedAssets) = morphoV2.liquidate(obligation, 0, repaid, 0, borrower, "");

        assertEq(repaidAssets, repaid, "repaid units");
        assertEq(
            seizedAssets, repaid.mulDivDown(ORACLE_PRICE_SCALE, 1e36 - 1).mulDivDown(MAX_LIF, WAD), "seized assets"
        );

        assertEq(morphoV2.debtOf(id, borrower), units - repaidAssets);
        assertEq(morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token), initialCollateral - seizedAssets);
        assertEq(loanToken.balanceOf(address(this)), 0);
    }

    function testLiquidateCollateralInput(uint256 units, uint256 seized) public {
        units = bound(units, 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        uint256 initialCollateral = morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token);
        seized = bound(seized, 0, units.mulDivDown(MAX_LIF, WAD));
        Oracle(obligation.collaterals[0].oracle).setPrice(1e36 - 1);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF); // Warp to post-maturity to bypass recovery close factor.
        uint256 repaid = seized.mulDivUp(WAD, MAX_LIF).mulDivUp(1e36 - 1, ORACLE_PRICE_SCALE);
        deal(address(loanToken), address(this), repaid);

        (uint256 repaidAssets, uint256 seizedAssets) = morphoV2.liquidate(obligation, 0, 0, seized, borrower, "");

        assertEq(repaidAssets, seized.mulDivUp(WAD, MAX_LIF).mulDivUp(1e36 - 1, ORACLE_PRICE_SCALE), "repaid units");
        assertEq(seizedAssets, seized, "seized assets");

        assertEq(loanToken.balanceOf(address(this)), 0, "loan token balance");
        assertEq(morphoV2.debtOf(id, borrower), units - repaidAssets, "debt");
        assertEq(
            morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token),
            initialCollateral - seizedAssets,
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
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF); // Warp to post-maturity to bypass recovery close factor.
        deal(address(loanToken), address(this), units);

        morphoV2.liquidate(obligation, 0, repaid, 0, borrower, data);

        assertEq(recordedRepaidAssets, repaid, "repaid units");
        assertEq(recordedData, data, "data");
    }

    function testCannotRepayMoreThanDebt(uint256 units, uint256 repaid) public {
        units = bound(units, 10, MAX_TEST_AMOUNT - 1);
        repaid = bound(repaid, units + 1, MAX_TEST_AMOUNT);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(1e36 - 1);
        deal(address(loanToken), address(this), units);
        deal(address(loanToken), address(this), units);

        vm.expectRevert(stdError.arithmeticError);
        morphoV2.liquidate(obligation, 0, repaid, 0, borrower, "");
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

        vm.expectRevert(stdError.arithmeticError);
        morphoV2.liquidate(obligation, 0, 0, seized, borrower, "");
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

        morphoV2.liquidate(obligation, 0, 0, 0, borrower, "");

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

        morphoV2.liquidate(obligation, 0, 0, seized, borrower, "");

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

        morphoV2.liquidate(obligation, 0, repaid, 0, borrower, "");

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

        morphoV2.liquidate(obligation, 0, 0, initialCollateral, borrower, "");

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

        morphoV2.liquidate(obligation, 0, repaid, 0, borrower, "");

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

        morphoV2.liquidate(obligation, 0, repaid, 0, borrower, "");

        uint256 lif = WAD + (MAX_LIF - WAD) * delay / TIME_TO_MAX_LIF;

        assertEq(morphoV2.debtOf(id, borrower), units - repaid, "debt");
        assertEq(
            morphoV2.collateralOf(id, borrower, obligation.collaterals[0].token),
            initialCollateral - repaid.mulDivDown(lif, WAD),
            "collateral"
        );
    }

    // recovery close factor

    function testCannotLiquidateMoreThanRecoveryCloseFactor(uint256 units) public {
        units = bound(units, 10, MAX_TEST_AMOUNT - 1);
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);
        Oracle(obligation.collaterals[0].oracle).setPrice(1e36 - 1);
        deal(address(loanToken), address(this), units);

        vm.expectRevert("recovery close factor violated");
        morphoV2.liquidate(obligation, 0, units, 0, borrower, "");
    }

    // gas tests

    /// forge-config: default.isolate = true
    function testGasLiquidateMultipleCollaterals() public {
        uint256 n = 25;
        uint256[] memory collateralCounts = new uint256[](n);

        for(uint256 i = 1; i <= n ; i++) {
            collateralCounts[i-1] = 2*i;
        }

        emit log("[");
        for (uint256 i = 0; i < collateralCounts.length; i++) {
            uint256 snapshot = vm.snapshotState();
            bool isLast = (i == collateralCounts.length - 1);
            _testGasLiquidateNCollaterals(collateralCounts[i], isLast);
            vm.revertToState(snapshot);
        }
        emit log("]");
    }

    function _testGasLiquidateNCollaterals(uint256 n, bool isLast) internal {
        require(n >= 1, "n must be at least 1");

        // Create N collateral tokens and oracles.
        ERC20[] memory collateralTokens = new ERC20[](n);
        Oracle[] memory oracles = new Oracle[](n);
        Collateral[] memory collaterals = new Collateral[](n);

        for (uint256 i = 0; i < n; i++) {
            collateralTokens[i] =
                new ERC20(string.concat("collat", vm.toString(i)), string.concat("C", vm.toString(i)));
            oracles[i] = new Oracle();
            collaterals[i] =
                Collateral({token: address(collateralTokens[i]), lltv: 0.75e18, oracle: address(oracles[i])});
        }
        collaterals = sortCollaterals(collaterals);

        // Create obligation with N collaterals.
        Obligation memory gasObligation;
        gasObligation.loanToken = address(loanToken);
        gasObligation.maturity = block.timestamp + 100;
        gasObligation.collaterals = collaterals;

        uint256 units = 1000e18;
        uint256 collateralAmount = units.mulDivUp(WAD, 0.75e18);

        // Supply all collaterals.
        for (uint256 i = 0; i < n; i++) {
            address token = gasObligation.collaterals[i].token;
            deal(token, address(this), collateralAmount);
            ERC20(token).approve(address(morphoV2), collateralAmount);
            morphoV2.supplyCollateral(gasObligation, token, collateralAmount, borrower);
        }

        // Setup obligation with debt.
        deal(address(loanToken), lender, units);
        Offer memory borrowerOffer;
        borrowerOffer.obligation = gasObligation;
        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.assets = units;
        borrowerOffer.start = block.timestamp;
        borrowerOffer.expiry = block.timestamp;
        borrowerOffer.tick = TICK_RANGE;
        morphoV2.take(
            0,
            0,
            units,
            0,
            lender,
            borrowerOffer,
            sig([borrowerOffer]),
            root([borrowerOffer]),
            proof([borrowerOffer]),
            address(0),
            hex""
        );

        // Make position liquidatable.
        for (uint256 i = 0; i < n; i++) {
            Oracle(gasObligation.collaterals[i].oracle).setPrice(0.5e36);
        }
        vm.warp(gasObligation.maturity + TIME_TO_MAX_LIF);
        deal(address(loanToken), address(this), units);
        uint256 repay = units / n;

        // Measure gas.
        bytes[] memory calls = new bytes[](n);
        for (uint256 i = 0; i < n; i++) {
            calls[i] = abi.encodeCall(morphoV2.liquidate, (gasObligation, i, repay, 0, borrower, ""));
        }

        uint256 gasBefore = gasleft();
        morphoV2.multicall(calls);
        uint256 gasUsed = gasBefore - gasleft();

        // Log gas results as JSON.
        string memory suffix = isLast ? "" : ",";
        emit log(
            string.concat('{"collaterals": ', vm.toString(n), ', "gas": ', vm.toString(gasUsed), "}", suffix)
        );
    }

    // helpers.

    function onLiquidate(Obligation memory, uint256, uint256, uint256 _repaidAssets, address, bytes memory data)
        public
    {
        recordedRepaidAssets = _repaidAssets;
        recordedData = data;
    }
}
