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
import {IMidnight, Market, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {BaseTest} from "./BaseTest.sol";
import {console} from "forge-std/console.sol";

interface IERC20Approve {
    function approve(address spender, uint256 amount) external returns (bool);
}

contract Liquidator {
    IMidnight public immutable midnight;

    constructor(address _midnight, address loanToken) {
        midnight = IMidnight(_midnight);
        IERC20Approve(loanToken).approve(_midnight, type(uint256).max);
    }

    function liquidateAll(Market calldata market, uint256 seizePerCall, address borrower) external {
        uint256 n = market.collateralParams.length;
        for (uint256 i = 0; i < n; i++) {
            midnight.liquidate(market, i, seizePerCall, 0, borrower, false, address(this), address(0), "");
        }
    }
}

contract GasTest is BaseTest {
    using UtilsLib for uint256;

    Market internal market;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();
        market.loanToken = address(loanToken);
        market.maturity = block.timestamp + 100;
        market.rcfThreshold = 0;
    }

    /// forge-config: default.isolate = true
    function testGasLiquidateSingleCollateral() public {
        uint256 lltv = 0.77e18;
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: lltv,
                    maxLif: maxLif(lltv, LIQUIDATION_CURSOR_LOW),
                    oracle: address(oracle1)
                })
            );
        id = toId(market);

        uint256 units = 1000e18;
        collateralize(market, borrower, units);
        setupMarket(market, units);

        // Make position liquidatable post-maturity at full LIF without overflowing collateral.
        oracle1.setPrice(0.9e36);
        vm.warp(market.maturity + TIME_TO_MAX_LIF);

        deal(address(loanToken), address(this), type(uint256).max);

        uint256 gasBefore = gasleft();
        midnight.liquidate(market, 0, 0, units, borrower, true, address(this), address(0), "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas single-collat liquidation", gasUsed);
    }

    /// forge-config: default.isolate = true
    function testGasLiquidateMaxCollaterals() public {
        uint256 gasUsed = _measureLiquidateN(MAX_COLLATERALS_PER_BORROWER);
        console.log("Gas max-collats liquidation", gasUsed);
    }

    /// forge-config: default.isolate = true
    function testGasLiquidateScalingJson() public {
        string memory json = "[\n";

        for (uint256 n = 1; n <= MAX_COLLATERALS_PER_BORROWER; n++) {
            uint256 snap = vm.snapshotState();
            uint256 gasUsed = _measureLiquidateN(n);
            console.log("n", n, "gas", gasUsed);
            json = string.concat(
                json,
                "  {\"n\": ",
                vm.toString(n),
                ", \"gas\": ",
                vm.toString(gasUsed),
                "}",
                n == MAX_COLLATERALS_PER_BORROWER ? "\n" : ",\n"
            );
            vm.revertToState(snap);
        }
        json = string.concat(json, "]\n");

        vm.writeFile("./test/gas_report.json", json);
    }

    function _measureLiquidateN(uint256 n) internal returns (uint256) {
        uint256 lltv = 0.77e18;
        uint256 _maxLif = maxLif(lltv, LIQUIDATION_CURSOR_LOW);

        // Build n unique collateral params (sorted by token address).
        CollateralParams[] memory params = new CollateralParams[](n);
        for (uint256 i = 0; i < n; i++) {
            ERC20 token = new ERC20("collat", "collat");
            Oracle o = new Oracle();
            params[i] = CollateralParams({token: address(token), lltv: lltv, maxLif: _maxLif, oracle: address(o)});
            token.approve(address(midnight), type(uint256).max);
        }
        params = sortCollateralParams(params);
        for (uint256 i = 0; i < n; i++) {
            market.collateralParams.push(params[i]);
        }
        id = toId(market);

        vm.prank(borrower);
        midnight.setIsAuthorized(address(this), true, borrower);

        // Each collateral covers debtPerCollat of debt capacity. units = n * debtPerCollat avoids
        // rounding gaps that would otherwise leave the position unhealthy at par for some n.
        uint256 debtPerCollat = 100e18;
        uint256 units = n * debtPerCollat;
        for (uint256 i = 0; i < n; i++) {
            CollateralParams memory cp = market.collateralParams[i];
            uint256 oraclePrice = Oracle(cp.oracle).price();
            uint256 collateral = debtPerCollat.mulDivUp(WAD, cp.lltv).mulDivUp(ORACLE_PRICE_SCALE, oraclePrice);
            deal(cp.token, address(this), collateral);
            midnight.supplyCollateral(market, i, collateral, borrower);
        }

        setupMarket(market, units);

        // Drop every oracle to make the position liquidatable.
        for (uint256 i = 0; i < n; i++) {
            Oracle(market.collateralParams[i].oracle).setPrice(0.9e36);
        }
        vm.warp(market.maturity + TIME_TO_MAX_LIF);

        // Deploy a liquidator contract that loops over every collateral, mimicking what a real
        // liquidator would do on-chain.
        Liquidator liquidator = new Liquidator(address(midnight), address(loanToken));
        deal(address(loanToken), address(liquidator), type(uint256).max);

        // A small fixed seize amount per call keeps both debt and collateral_i strictly positive
        // across the whole batch.
        uint256 seizePerCall = 1e18;

        uint256 gasBefore = gasleft();
        liquidator.liquidateAll(market, seizePerCall, borrower);
        return gasBefore - gasleft();
    }
}
