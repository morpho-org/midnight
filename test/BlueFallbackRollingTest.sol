// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IMorpho, Id, MarketParams} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Market, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {BlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/BlueFallbackRolling.sol";
import {IBlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/IBlueFallbackRolling.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

contract BlueFallbackRollingTest is BaseTest {
    using MarketParamsLib for MarketParams;

    uint256 internal constant BLUE_LLTV = 0.86e18;
    uint64 internal constant INCENTIVE_AT_START = 0.0002e18;
    uint64 internal constant INCENTIVE_AT_END = 0.001e18;
    uint64 internal constant MAX_INCENTIVE = 1e18;
    uint256 internal constant DEBT = 10_000e18;

    address internal keeper = makeAddr("keeper");
    IMorpho internal blue;
    BlueFallbackRolling internal fallbackContract;
    Market internal midnightMarket;
    MarketParams internal blueMarketParams;
    uint256 internal blueCollateralIndex;
    uint64 internal start;
    uint64 internal end;

    function setUp() public override {
        super.setUp();
        start = uint64(vm.getBlockTimestamp());
        // Deliberately different from the Midnight maturity: the auction period is independent of it.
        end = start + 12 hours;

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
        fallbackContract.setConfig(
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            true
        );
    }

    function testAnyoneCanRollBorrowerToBlue() public {
        uint256 midnightCollateral = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.warp(end);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT
        );

        uint256 incentiveAssets = DEBT * INCENTIVE_AT_END / WAD;
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
        vm.warp(end);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, debtAssets
        );

        uint256 incentiveAssets = debtAssets * INCENTIVE_AT_END / WAD;
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

    function testIncentiveIsTheStartIncentiveBeforeAndAtStart() public view {
        assertEq(fallbackContract.incentive(start + 1, end, INCENTIVE_AT_START, INCENTIVE_AT_END), INCENTIVE_AT_START);
        assertEq(fallbackContract.incentive(start, end, INCENTIVE_AT_START, INCENTIVE_AT_END), INCENTIVE_AT_START);
    }

    function testIncentiveGrowsLinearlyUntilEnd(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, end - start);
        vm.warp(start + elapsed);

        assertEq(
            fallbackContract.incentive(start, end, INCENTIVE_AT_START, INCENTIVE_AT_END), expectedIncentive(elapsed)
        );
    }

    function testIncentiveIsFlatWhenBothBoundsAreEqual(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, end - start);
        vm.warp(start + elapsed);

        assertEq(fallbackContract.incentive(start, end, INCENTIVE_AT_START, INCENTIVE_AT_START), INCENTIVE_AT_START);
    }

    function testIncentiveIsCappedAfterEnd(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, 100 * 365 days);
        vm.warp(end + elapsed);

        assertEq(fallbackContract.incentive(start, end, INCENTIVE_AT_START, INCENTIVE_AT_END), INCENTIVE_AT_END);
    }

    function testIncentiveIsTheEndIncentiveWhenTheAuctionIsInstant() public view {
        assertEq(fallbackContract.incentive(start, start, INCENTIVE_AT_START, INCENTIVE_AT_END), INCENTIVE_AT_END);
    }

    function testRollPaysTheAuctionedIncentive(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, end - start);
        vm.warp(start + elapsed);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT
        );

        assertEq(loanToken.balanceOf(keeper), DEBT * expectedIncentive(elapsed) / WAD);
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    /// @dev The auction can be configured to end after the Midnight maturity.
    function testRollPaysTheAuctionedIncentiveWhenTheAuctionEndsAfterMaturity() public {
        uint64 lateEnd = uint64(midnightMarket.maturity) + 1 days;
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            lateEnd,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            true
        );
        vm.warp(midnightMarket.maturity);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, lateEnd, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT
        );

        uint256 elapsed = midnightMarket.maturity - start;
        uint256 expected = INCENTIVE_AT_START + (INCENTIVE_AT_END - INCENTIVE_AT_START) * elapsed / (lateEnd - start);
        assertLt(expected, INCENTIVE_AT_END);
        assertEq(loanToken.balanceOf(keeper), DEBT * expected / WAD);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testRollAtStartPaysTheStartIncentive() public {
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT
        );

        assertEq(loanToken.balanceOf(keeper), DEBT * INCENTIVE_AT_START / WAD);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    /// @dev Measures the gas of a full roll: supplyCollateral on Blue, borrow on Blue, repay and
    /// withdrawCollateral on Midnight, plus the incentive transfer. Rolls at `end` so the incentive is maximal.
    function testGasFullRoll() public {
        vm.warp(end);

        // Copy the params to memory beforehand so the gasleft() window only covers the roll itself.
        Market memory _midnightMarket = midnightMarket;
        MarketParams memory _blueMarketParams = blueMarketParams;

        vm.prank(keeper);
        uint256 gasBefore = gasleft();
        fallbackContract.roll(
            _midnightMarket, _blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT
        );
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas: full roll", gasUsed);

        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testCannotRollBeforeStart() public {
        uint64 futureStart = uint64(vm.getBlockTimestamp() + 1);
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            futureStart,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            true
        );

        vm.expectRevert(IBlueFallbackRolling.NotStarted.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, futureStart, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT
        );
    }

    function testCannotRollAfterEnd(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, 365 days);
        vm.warp(end + elapsed);

        vm.expectRevert(IBlueFallbackRolling.Ended.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT
        );
    }

    function testRollRevertsForUnconfiguredBlueMarket() public {
        blueMarketParams.oracle = makeAddr("otherOracle");

        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT
        );
    }

    function testRollRevertsForUnconfiguredEnd() public {
        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end + 1, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT
        );
    }

    function testRollRevertsForInconsistentLoanToken() public {
        blueMarketParams.loanToken = makeAddr("otherLoanToken");
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            true
        );

        vm.expectRevert(IBlueFallbackRolling.InconsistentLoanToken.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT
        );
    }

    function testRollRevertsForMultipleActivatedCollaterals() public {
        collateralize(midnightMarket, borrower, DEBT, 1 - blueCollateralIndex);

        vm.expectRevert(IBlueFallbackRolling.IncorrectActivatedCollateral.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT
        );
    }

    function testRollRevertsWhenActivatedCollateralDoesNotMatchBlue() public {
        uint256 otherCollateralIndex = 1 - blueCollateralIndex;
        collateralize(midnightMarket, borrower, DEBT, otherCollateralIndex);
        uint256 blueCollateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.prank(borrower);
        midnight.withdrawCollateral(midnightMarket, blueCollateralIndex, blueCollateralAssets, borrower, borrower);

        vm.expectRevert(IBlueFallbackRolling.InconsistentCollateralToken.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT
        );
    }

    function testSupplyCollateralCallbackRevertsIfCallerIsNotBlue() public {
        uint256 collateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.expectRevert(IBlueFallbackRolling.NotBlue.selector);
        fallbackContract.onMorphoSupplyCollateral(
            collateralAssets,
            abi.encode(
                midnightMarket, blueMarketParams, blueCollateralIndex, DEBT, DEBT * INCENTIVE_AT_END / WAD, borrower
            )
        );
    }

    function testSetConfig() public view {
        assertTrue(fallbackContract.isConfig(borrower, configId(start, end, INCENTIVE_AT_START, INCENTIVE_AT_END)));
    }

    function testSetConfigRevertsForTooLargeIncentive() public {
        uint64 incentiveAtEnd = MAX_INCENTIVE + 1;

        vm.expectRevert(IBlueFallbackRolling.IncentiveTooHigh.selector);
        fallbackContract.setConfig(
            toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, end, INCENTIVE_AT_START, incentiveAtEnd, true
        );
    }

    function testSetConfigRevertsForDecreasingIncentive() public {
        vm.expectRevert(IBlueFallbackRolling.IncentiveNotIncreasing.selector);
        fallbackContract.setConfig(
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_END + 1,
            INCENTIVE_AT_END,
            true
        );
    }

    function testSetConfigRevertsForEndBeforeStart() public {
        vm.expectRevert(IBlueFallbackRolling.EndBeforeStart.selector);
        fallbackContract.setConfig(
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            start - 1,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            true
        );
    }

    function testSetConfigAllowsOneIncentive() public {
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, end, MAX_INCENTIVE, MAX_INCENTIVE, true
        );

        assertTrue(fallbackContract.isConfig(borrower, configId(start, end, MAX_INCENTIVE, MAX_INCENTIVE)));
    }

    function testSetConfigCanDisable() public {
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            false
        );

        assertFalse(fallbackContract.isConfig(borrower, configId(start, end, INCENTIVE_AT_START, INCENTIVE_AT_END)));

        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT
        );
    }

    function testSetConfigDoesNotReplaceOtherConfig() public {
        uint64 otherStart = start + 1;
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket), Id.unwrap(blueMarketParams.id()), otherStart, end, MAX_INCENTIVE, MAX_INCENTIVE, true
        );

        assertTrue(fallbackContract.isConfig(borrower, configId(start, end, INCENTIVE_AT_START, INCENTIVE_AT_END)));
        assertTrue(fallbackContract.isConfig(borrower, configId(otherStart, end, MAX_INCENTIVE, MAX_INCENTIVE)));
    }

    /// @dev The incentive `elapsed` seconds into the auction, interpolated between the two configured bounds.
    function expectedIncentive(uint256 elapsed) internal view returns (uint256) {
        uint256 duration = end - start;
        return INCENTIVE_AT_START + (INCENTIVE_AT_END - INCENTIVE_AT_START) * elapsed / duration;
    }

    function configId(uint64 _start, uint64 _end, uint64 incentiveAtStart, uint64 incentiveAtEnd)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                toId(midnightMarket), Id.unwrap(blueMarketParams.id()), _start, _end, incentiveAtStart, incentiveAtEnd
            )
        );
    }
}
