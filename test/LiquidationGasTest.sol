// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {console} from "../lib/forge-std/src/Test.sol";
import {MAX_COLLATERALS, MAX_COLLATERALS_PER_BORROWER, TIME_TO_MAX_LIF} from "../src/libraries/ConstantsLib.sol";
import {Market, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {IdLib} from "../src/libraries/IdLib.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

contract LiquidationGasTest is BaseTest {
    Market internal market;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        // The market defines the maximum number of collaterals it supports...
        CollateralParams[] memory collateralParams = new CollateralParams[](MAX_COLLATERALS);
        for (uint256 i = 0; i < MAX_COLLATERALS; i++) {
            collateralParams[i] = CollateralParams({
                token: address(new ERC20("", "")),
                lltv: LLTV,
                liquidationCursor: LIQUIDATION_CURSOR,
                oracle: address(new Oracle())
            });
        }
        collateralParams = sortCollateralParams(collateralParams);

        market.loanToken = address(loanToken);
        market.chainId = block.chainid;
        market.midnight = address(midnight);
        market.maturity = vm.getBlockTimestamp() + 100;
        market.collateralParams = collateralParams;
        market.rcfThreshold = 0;

        id = IdLib.toId(market);

        deal(address(loanToken), address(this), type(uint256).max);
    }

    /// forge-config: default.isolate = true
    function testLiquidateSingleCollateralGas() public {
        uint256 unitsPerCollateral = 100e18;

        // ...and the borrower's position holds the maximum number of collaterals
        // a single position can hold (MAX_COLLATERALS_PER_BORROWER, out of the
        // market's MAX_COLLATERALS), so liquidate() walks a full collateralBitmap
        // while only seizing/repaying against one of them.
        for (uint256 i = 0; i < MAX_COLLATERALS_PER_BORROWER; i++) {
            collateralize(market, borrower, unitsPerCollateral, i);
        }
        setupMarket(market, unitsPerCollateral * MAX_COLLATERALS_PER_BORROWER);

        // Warp past maturity (and past the LIF ramp-up) so the full debt backed by
        // the targeted collateral can be repaid and seized in a single call.
        vm.warp(market.maturity + TIME_TO_MAX_LIF);

        midnight.liquidate(market, 0, 0, unitsPerCollateral, borrower, true, address(this), address(0), "");

        console.log("liquidate (1 of %s collaterals held) gas used:", MAX_COLLATERALS_PER_BORROWER);
        console.log(vm.lastCallGas().gasTotalUsed);
    }
}
