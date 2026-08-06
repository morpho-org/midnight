// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IMorpho, Id, MarketParams} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Market, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {BlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/BlueFallbackRolling.sol";
import {IBlueFallbackRolling, Config} from "../src/periphery/blue-fallback-rolling/IBlueFallbackRolling.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

contract BlueFallbackRollingTest is BaseTest {
    using MarketParamsLib for MarketParams;

    uint256 internal constant BLUE_LLTV = 0.86e18;
    uint64 internal constant INCENTIVE = 0.001e18;
    uint64 internal constant MAX_INCENTIVE = 1e18;
    uint256 internal constant DEBT = 10_000e18;

    address internal keeper = makeAddr("keeper");
    IMorpho internal blue;
    BlueFallbackRolling internal fallbackContract;
    Market internal midnightMarket;
    MarketParams internal blueMarketParams;
    uint256 internal blueCollateralIndex;
    uint64 internal rollWindow;

    function setUp() public override {
        super.setUp();
        // The market matures in 1 day, so a 1-day window is open from now on.
        rollWindow = 1 days;

        blue = IMorpho(deployCode("Morpho.sol", abi.encode(address(this))));
        blue.enableIrm(address(0));
        blue.enableLltv(BLUE_LLTV);

        blueMarketParams = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken1),
            oracle: address(oracle1),
            irm: address(0),
            lltv: BLUE_LLTV
        });
        blue.createMarket(blueMarketParams);

        fallbackContract = new BlueFallbackRolling(address(midnight), address(blue));

        midnightMarket.loanToken = address(loanToken);
        midnightMarket.chainId = block.chainid;
        midnightMarket.midnight = address(midnight);
        midnightMarket.maturity = vm.getBlockTimestamp() + 1 days;
        midnightMarket.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: LLTV,
                    liquidationCursor: LIQUIDATION_CURSOR,
                    oracle: address(oracle1)
                })
            );
        midnightMarket.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: LLTV,
                    liquidationCursor: LIQUIDATION_CURSOR,
                    oracle: address(oracle2)
                })
            );
        midnightMarket.collateralParams = sortCollateralParams(midnightMarket.collateralParams);
        blueCollateralIndex = midnightMarket.collateralParams[0].token == address(collateralToken1) ? 0 : 1;

        collateralize(midnightMarket, borrower, DEBT, blueCollateralIndex);
        setupMarket(midnightMarket, DEBT);

        deal(address(loanToken), address(this), 2 * DEBT);
        loanToken.approve(address(blue), type(uint256).max);
        blue.supply(blueMarketParams, 2 * DEBT, 0, lender, hex"");

        vm.prank(borrower);
        midnight.setIsAuthorized(address(fallbackContract), true, borrower);
        vm.prank(borrower);
        blue.setAuthorization(address(fallbackContract), true);
        vm.prank(borrower);
        setConfig(config(rollWindow, INCENTIVE), true);
    }

    function testAnyoneCanRollBorrowerToBlue() public {
        uint256 midnightCollateral = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);

        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, config(rollWindow, INCENTIVE), DEBT);

        uint256 incentiveAssets = DEBT * INCENTIVE / WAD;
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
        assertEq(midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex), 0);
        assertEq(blue.position(blueMarketParams.id(), borrower).collateral, midnightCollateral);
        assertGt(blue.position(blueMarketParams.id(), borrower).borrowShares, 0);
        assertEq(loanToken.balanceOf(keeper), incentiveAssets);
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0);
    }

    function testAnyoneCanPartiallyRollBorrowerToBlue() public {
        uint256 totalCollateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        uint256 debtAssets = DEBT / 2;
        uint256 collateralAssets = totalCollateralAssets * debtAssets / DEBT;

        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, config(rollWindow, INCENTIVE), debtAssets);

        uint256 incentiveAssets = debtAssets * INCENTIVE / WAD;
        assertEq(midnight.debt(toId(midnightMarket), borrower), DEBT - debtAssets);
        assertEq(
            midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex),
            totalCollateralAssets - collateralAssets
        );
        assertEq(blue.position(blueMarketParams.id(), borrower).collateral, collateralAssets);
        assertGt(blue.position(blueMarketParams.id(), borrower).borrowShares, 0);
        assertEq(loanToken.balanceOf(keeper), incentiveAssets);
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0);
    }

    function testCannotRollBeforeRollWindowOpens() public {
        // The window opens 1 second from now.
        uint64 shorterWindow = rollWindow - 1;
        vm.prank(borrower);
        setConfig(config(shorterWindow, INCENTIVE), true);

        vm.expectRevert(IBlueFallbackRolling.RollWindowNotOpen.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, config(shorterWindow, INCENTIVE), DEBT);

        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, config(shorterWindow, INCENTIVE), DEBT);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testCanRollWhenRollWindowExceedsMaturity() public {
        uint64 hugeWindow = type(uint64).max;
        vm.prank(borrower);
        setConfig(config(hugeWindow, INCENTIVE), true);

        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, config(hugeWindow, INCENTIVE), DEBT);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testRollRevertsForUnconfiguredBlueMarket() public {
        blueMarketParams.oracle = makeAddr("otherOracle");

        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, config(rollWindow, INCENTIVE), DEBT);
    }

    function testRollRevertsForInconsistentLoanToken() public {
        blueMarketParams.loanToken = makeAddr("otherLoanToken");
        vm.prank(borrower);
        setConfig(config(rollWindow, INCENTIVE), true);

        vm.expectRevert(IBlueFallbackRolling.InconsistentLoanToken.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, config(rollWindow, INCENTIVE), DEBT);
    }

    function testRollRevertsForMultipleActivatedCollaterals() public {
        collateralize(midnightMarket, borrower, DEBT, 1 - blueCollateralIndex);

        vm.expectRevert(IBlueFallbackRolling.IncorrectActivatedCollateral.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, config(rollWindow, INCENTIVE), DEBT);
    }

    function testRollRevertsWhenActivatedCollateralDoesNotMatchBlue() public {
        uint256 otherCollateralIndex = 1 - blueCollateralIndex;
        collateralize(midnightMarket, borrower, DEBT, otherCollateralIndex);
        uint256 blueCollateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.prank(borrower);
        midnight.withdrawCollateral(midnightMarket, blueCollateralIndex, blueCollateralAssets, borrower, borrower);

        vm.expectRevert(IBlueFallbackRolling.InconsistentCollateralToken.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, config(rollWindow, INCENTIVE), DEBT);
    }

    function testSupplyCollateralCallbackRevertsIfCallerIsNotBlue() public {
        uint256 collateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.expectRevert(IBlueFallbackRolling.NotBlue.selector);
        fallbackContract.onMorphoSupplyCollateral(
            collateralAssets,
            abi.encode(midnightMarket, blueMarketParams, blueCollateralIndex, DEBT, DEBT * INCENTIVE / WAD, borrower)
        );
    }

    function testSetConfig() public view {
        assertTrue(fallbackContract.isConfig(borrower, configId(rollWindow, INCENTIVE)));
    }

    function testSetConfigRevertsForTooLargeIncentive() public {
        uint64 incentive = MAX_INCENTIVE + 1;

        vm.expectRevert(IBlueFallbackRolling.IncentiveTooHigh.selector);
        setConfig(config(rollWindow, incentive), true);
    }

    function testSetConfigAllowsOneIncentive() public {
        vm.prank(borrower);
        setConfig(config(rollWindow, MAX_INCENTIVE), true);

        assertTrue(fallbackContract.isConfig(borrower, configId(rollWindow, MAX_INCENTIVE)));
    }

    function testSetConfigCanDisable() public {
        vm.prank(borrower);
        setConfig(config(rollWindow, INCENTIVE), false);

        assertFalse(fallbackContract.isConfig(borrower, configId(rollWindow, INCENTIVE)));

        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, config(rollWindow, INCENTIVE), DEBT);
    }

    function testSetConfigDoesNotReplaceOtherConfig() public {
        uint64 otherRollWindow = rollWindow + 1;
        vm.prank(borrower);
        setConfig(config(otherRollWindow, MAX_INCENTIVE), true);

        assertTrue(fallbackContract.isConfig(borrower, configId(rollWindow, INCENTIVE)));
        assertTrue(fallbackContract.isConfig(borrower, configId(otherRollWindow, MAX_INCENTIVE)));
    }

    function setConfig(Config memory _config, bool enabled) internal {
        fallbackContract.setConfig(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), _config, enabled);
    }

    function configId(uint64 _rollWindow, uint64 incentive) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(toId(midnightMarket), Id.unwrap(blueMarketParams.id()), config(_rollWindow, incentive))
            );
    }

    function config(uint64 _rollWindow, uint64 incentive) internal pure returns (Config memory) {
        return Config({rollWindow: _rollWindow, incentive: incentive});
    }
}
