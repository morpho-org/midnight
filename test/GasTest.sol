// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {
    WAD,
    ORACLE_PRICE_SCALE,
    TIME_TO_MAX_LIF,
    LIQUIDATION_CURSOR_LOW,
    MAX_COLLATERALS_PER_BORROWER
} from "../src/libraries/ConstantsLib.sol";
import {Obligation, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {BaseTest} from "./BaseTest.sol";
import {console} from "forge-std/console.sol";

contract GasTest is BaseTest {
    using UtilsLib for uint256;

    Obligation internal obligation;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.rcfThreshold = 0;
    }

    /// forge-config: default.isolate = true
    function testGasLiquidateSingleCollateral() public {
        uint256 lltv = 0.77e18;
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: lltv,
                    maxLif: maxLif(lltv, LIQUIDATION_CURSOR_LOW),
                    oracle: address(oracle1)
                })
            );
        id = toId(obligation);

        uint256 units = 1000e18;
        collateralize(obligation, borrower, units);
        setupObligation(obligation, units);

        // Make position liquidatable post-maturity at full LIF without overflowing collateral.
        oracle1.setPrice(0.9e36);
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF);

        deal(address(loanToken), address(this), type(uint256).max);

        uint256 gasBefore = gasleft();
        midnight.liquidate(obligation, 0, 0, units, borrower, address(this), address(0), "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas single-collat liquidation", gasUsed);
    }

    /// forge-config: default.isolate = true
    function testGasLiquidateMaxCollaterals() public {
        uint256 lltv = 0.77e18;
        uint256 _maxLif = maxLif(lltv, LIQUIDATION_CURSOR_LOW);

        // Build MAX_COLLATERALS_PER_BORROWER unique collateral params (sorted by token address).
        CollateralParams[] memory params = new CollateralParams[](MAX_COLLATERALS_PER_BORROWER);
        for (uint256 i = 0; i < MAX_COLLATERALS_PER_BORROWER; i++) {
            ERC20 token = new ERC20("collat", "collat");
            Oracle o = new Oracle();
            params[i] = CollateralParams({token: address(token), lltv: lltv, maxLif: _maxLif, oracle: address(o)});
            token.approve(address(midnight), type(uint256).max);
        }
        params = sortCollateralParams(params);
        for (uint256 i = 0; i < MAX_COLLATERALS_PER_BORROWER; i++) {
            obligation.collateralParams.push(params[i]);
        }
        id = toId(obligation);

        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, address(this), true);

        // Each collateral covers ~ units/N of debt capacity, so the position is healthy at par.
        uint256 units = 1000e18;
        uint256 debtPerCollat = units / MAX_COLLATERALS_PER_BORROWER;
        for (uint256 i = 0; i < MAX_COLLATERALS_PER_BORROWER; i++) {
            CollateralParams memory cp = obligation.collateralParams[i];
            uint256 oraclePrice = Oracle(cp.oracle).price();
            uint256 collateral = debtPerCollat.mulDivUp(WAD, cp.lltv).mulDivUp(ORACLE_PRICE_SCALE, oraclePrice);
            deal(cp.token, address(this), collateral);
            midnight.supplyCollateral(obligation, i, collateral, borrower);
        }

        setupObligation(obligation, units);

        // Drop every oracle to make the position liquidatable.
        for (uint256 i = 0; i < MAX_COLLATERALS_PER_BORROWER; i++) {
            Oracle(obligation.collateralParams[i].oracle).setPrice(0.9e36);
        }
        vm.warp(obligation.maturity + TIME_TO_MAX_LIF);

        deal(address(loanToken), address(this), type(uint256).max);

        // Liquidate every collateral once in a multicall. A small fixed seize amount per call keeps
        // both debt and collateral_i strictly positive across the whole batch.
        uint256 seizePerCall = 1e18;
        bytes[] memory calls = new bytes[](MAX_COLLATERALS_PER_BORROWER);
        for (uint256 i = 0; i < MAX_COLLATERALS_PER_BORROWER; i++) {
            calls[i] = abi.encodeCall(
                midnight.liquidate, (obligation, i, seizePerCall, 0, borrower, address(this), address(0), "")
            );
        }

        uint256 gasBefore = gasleft();
        midnight.multicall(calls);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas max-collats liquidation", gasUsed);
    }
}
