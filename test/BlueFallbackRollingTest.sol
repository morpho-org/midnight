// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IMorpho, Id, MarketParams} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IRepayCallback} from "../src/interfaces/ICallbacks.sol";
import {IMidnight, Market, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS, WAD} from "../src/libraries/ConstantsLib.sol";
import {BlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/BlueFallbackRolling.sol";
import {IBlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/IBlueFallbackRolling.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

contract BlueFallbackRollingTest is BaseTest {
    using MarketParamsLib for MarketParams;

    uint256 internal constant BLUE_LLTV = 0.86e18;
    int256 internal constant INCENTIVE_AT_START = 0.0002e18;
    int256 internal constant INCENTIVE_AT_END = 0.001e18;
    int256 internal constant MAX_INCENTIVE = 1e18;
    int256 internal constant MIN_INCENTIVE = -1e18;
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
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT, hex""
        );

        uint256 incentiveAssets = DEBT * uint256(INCENTIVE_AT_END) / WAD;
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
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            debtAssets,
            hex""
        );

        uint256 incentiveAssets = debtAssets * uint256(INCENTIVE_AT_END) / WAD;
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

    /// @dev A negative incentive is a premium paid by the caller, auctioned down to a positive incentive.
    function testIncentiveCanBeNegativeAndCrossZero() public {
        int256 incentiveAtStart = -0.001e18;
        uint256 duration = end - start;

        assertEq(fallbackContract.incentive(start, end, incentiveAtStart, -incentiveAtStart), incentiveAtStart);

        vm.warp(start + duration / 2);
        assertEq(fallbackContract.incentive(start, end, incentiveAtStart, -incentiveAtStart), 0);

        vm.warp(end);
        assertEq(fallbackContract.incentive(start, end, incentiveAtStart, -incentiveAtStart), -incentiveAtStart);
    }

    function testIncentiveStaysWithinBoundsWithANegativeStart(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, end - start);
        vm.warp(start + elapsed);

        int256 result = fallbackContract.incentive(start, end, MIN_INCENTIVE, INCENTIVE_AT_END);

        assertGe(result, MIN_INCENTIVE);
        assertLe(result, INCENTIVE_AT_END);
    }

    function testRollPaysTheAuctionedIncentive(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, end - start);
        vm.warp(start + elapsed);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT, hex""
        );

        assertEq(loanToken.balanceOf(keeper), DEBT * uint256(expectedIncentive(elapsed)) / WAD);
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
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            lateEnd,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            DEBT,
            hex""
        );

        int256 elapsed = int256(midnightMarket.maturity - start);
        int256 expected =
            INCENTIVE_AT_START + (INCENTIVE_AT_END - INCENTIVE_AT_START) * elapsed / int256(uint256(lateEnd - start));
        assertLt(expected, INCENTIVE_AT_END);
        assertEq(loanToken.balanceOf(keeper), DEBT * uint256(expected) / WAD);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testRollAtStartPaysTheStartIncentive() public {
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT, hex""
        );

        assertEq(loanToken.balanceOf(keeper), DEBT * uint256(INCENTIVE_AT_START) / WAD);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    /// @dev With a negative incentive the caller pays a premium, which is repaid on Blue on behalf of the user.
    function testRollWithANegativeIncentiveMakesTheCallerPayAPremium() public {
        int256 incentiveWad = -0.01e18;
        uint256 premiumAssets = DEBT * uint256(-incentiveWad) / WAD;
        setBorrowerConfig(start, end, incentiveWad, incentiveWad);
        fundKeeper(premiumAssets);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, incentiveWad, incentiveWad, DEBT, hex""
        );

        assertEq(loanToken.balanceOf(keeper), 0);
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
        assertGt(blue.position(blueMarketParams.id(), borrower).borrowShares, 0);
        assertEq(blue.market(blueMarketParams.id()).totalBorrowAssets, DEBT - premiumAssets);
    }

    /// @dev At the minimal incentive the premium repays the whole debt just borrowed on Blue.
    function testRollWithAFullPremiumLeavesNoDebtOnBlue() public {
        uint256 midnightCollateral = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        setBorrowerConfig(start, end, MIN_INCENTIVE, MIN_INCENTIVE);
        fundKeeper(DEBT);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, MIN_INCENTIVE, MIN_INCENTIVE, DEBT, hex""
        );

        assertEq(loanToken.balanceOf(keeper), 0);
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0);
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
        assertEq(blue.position(blueMarketParams.id(), borrower).collateral, midnightCollateral);
        assertEq(blue.position(blueMarketParams.id(), borrower).borrowShares, 0);
        assertEq(blue.market(blueMarketParams.id()).totalBorrowAssets, 0);
    }

    /// @dev The premium is rounded up, in favor of the borrower: it repays 1 wei more of the debt on Blue.
    function testRollRoundsThePremiumUp() public {
        int256 incentiveWad = -1;
        uint256 assets = 1e18 + 1;
        setBorrowerConfig(start, end, incentiveWad, incentiveWad);
        fundKeeper(2);

        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, incentiveWad, incentiveWad, assets, hex""
        );

        // The exact premium is 1.000...001 wei, rounded up to 2.
        assertEq(loanToken.balanceOf(keeper), 0);
        assertEq(blue.market(blueMarketParams.id()).totalBorrowAssets, assets - 2);
    }

    function testRollRevertsWhenTheCallerCannotPayThePremium() public {
        setBorrowerConfig(start, end, MIN_INCENTIVE, MIN_INCENTIVE);

        vm.expectRevert();
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, MIN_INCENTIVE, MIN_INCENTIVE, DEBT, hex""
        );
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
            _midnightMarket, _blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT, hex""
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
            midnightMarket,
            blueMarketParams,
            borrower,
            futureStart,
            end,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            DEBT,
            hex""
        );
    }

    function testRollRevertsForUnconfiguredBlueMarket() public {
        blueMarketParams.oracle = makeAddr("otherOracle");

        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT, hex""
        );
    }

    function testRollRevertsForUnconfiguredEnd() public {
        vm.expectRevert(IBlueFallbackRolling.NotConfigured.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket,
            blueMarketParams,
            borrower,
            start,
            end + 1,
            INCENTIVE_AT_START,
            INCENTIVE_AT_END,
            DEBT,
            hex""
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
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT, hex""
        );
    }

    function testRollRevertsForMultipleActivatedCollaterals() public {
        collateralize(midnightMarket, borrower, DEBT, 1 - blueCollateralIndex);

        vm.expectRevert(IBlueFallbackRolling.IncorrectActivatedCollateral.selector);
        vm.prank(keeper);
        fallbackContract.roll(
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT, hex""
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
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT, hex""
        );
    }

    function testSupplyCollateralCallbackRevertsIfCallerIsNotBlue() public {
        uint256 collateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.expectRevert(IBlueFallbackRolling.NotBlue.selector);
        fallbackContract.onMorphoSupplyCollateral(
            collateralAssets,
            abi.encode(
                midnightMarket,
                blueMarketParams,
                blueCollateralIndex,
                DEBT,
                DEBT + DEBT * uint256(INCENTIVE_AT_END) / WAD,
                borrower,
                address(this),
                hex""
            )
        );
    }

    function testRollCallsBackTheRollerWithItsData() public {
        RollerMock roller = new RollerMock(address(fallbackContract), CALLBACK_SUCCESS);
        bytes memory rollerData = hex"c0ffee";

        roller.rollWith(rollCalldata(DEBT, rollerData));

        assertTrue(roller.called());
        assertEq(roller.callbackCaller(), address(fallbackContract));
        assertEq(roller.id(), toId(midnightMarket));
        assertEq(roller.units(), DEBT);
        assertEq(roller.onBehalf(), borrower);
        assertEq(roller.data(), rollerData);
        // The roll still goes through, and the roller is paid the incentive as any other caller.
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
        assertEq(loanToken.balanceOf(address(roller)), DEBT * uint256(INCENTIVE_AT_START) / WAD);
        assertEq(loanToken.balanceOf(address(fallbackContract)), 0);
    }

    /// @dev The debt is already repaid on Midnight when the roller is called back.
    function testRollerCallbackSeesTheRepaidDebt() public {
        RollerMock roller = new RollerMock(address(fallbackContract), CALLBACK_SUCCESS);
        roller.watchDebt(address(midnight), toId(midnightMarket), borrower);

        roller.rollWith(rollCalldata(DEBT, hex"c0ffee"));

        assertEq(roller.debtDuringCallback(), 0);
    }

    /// @dev A caller that does not pass data is not called back, so an EOA can roll.
    function testRollDoesNotCallBackTheRollerWithoutData() public {
        RollerMock roller = new RollerMock(address(fallbackContract), CALLBACK_SUCCESS);

        roller.rollWith(rollCalldata(DEBT, hex""));

        assertFalse(roller.called());
        assertEq(midnight.debt(toId(midnightMarket), borrower), 0);
    }

    function testRollRevertsIfTheRollerCallbackReturnsAWrongValue() public {
        RollerMock roller = new RollerMock(address(fallbackContract), bytes32(0));

        vm.expectRevert(IBlueFallbackRolling.WrongRollerCallbackReturnValue.selector);
        roller.rollWith(rollCalldata(DEBT, hex"c0ffee"));
    }

    function testRepayCallbackRevertsIfCallerIsNotMidnight() public {
        vm.expectRevert(IBlueFallbackRolling.NotMidnight.selector);
        fallbackContract.onRepay(
            toId(midnightMarket), midnightMarket, DEBT, borrower, abi.encode(address(this), hex"c0ffee")
        );
    }

    function testSetConfig() public view {
        assertTrue(fallbackContract.isConfig(borrower, configId(start, end, INCENTIVE_AT_START, INCENTIVE_AT_END)));
    }

    function testSetConfigRevertsForTooLargeIncentive() public {
        int256 incentiveAtEnd = MAX_INCENTIVE + 1;

        vm.expectRevert(IBlueFallbackRolling.IncentiveTooHigh.selector);
        fallbackContract.setConfig(
            toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, end, INCENTIVE_AT_START, incentiveAtEnd, true
        );
    }

    function testSetConfigRevertsForTooLowIncentive() public {
        vm.expectRevert(IBlueFallbackRolling.IncentiveTooLow.selector);
        fallbackContract.setConfig(
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            end,
            MIN_INCENTIVE - 1,
            INCENTIVE_AT_END,
            true
        );
    }

    function testSetConfigAllowsNegativeIncentives() public {
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket), Id.unwrap(blueMarketParams.id()), start, end, MIN_INCENTIVE, MIN_INCENTIVE, true
        );

        assertTrue(fallbackContract.isConfig(borrower, configId(start, end, MIN_INCENTIVE, MIN_INCENTIVE)));
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
            midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, DEBT, hex""
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

    function setBorrowerConfig(uint64 _start, uint64 _end, int256 incentiveAtStart, int256 incentiveAtEnd) internal {
        vm.prank(borrower);
        fallbackContract.setConfig(
            toId(midnightMarket), Id.unwrap(blueMarketParams.id()), _start, _end, incentiveAtStart, incentiveAtEnd, true
        );
    }

    /// @dev The calldata of a roll of `assets` on the borrower's configured markets, passing `data` to the caller.
    function rollCalldata(uint256 assets, bytes memory data) internal view returns (bytes memory) {
        return abi.encodeCall(
            IBlueFallbackRolling.roll,
            (midnightMarket, blueMarketParams, borrower, start, end, INCENTIVE_AT_START, INCENTIVE_AT_END, assets, data)
        );
    }

    /// @dev Gives the keeper exactly `assets` loan tokens to pay a premium with.
    function fundKeeper(uint256 assets) internal {
        deal(address(loanToken), keeper, assets);
        vm.prank(keeper);
        loanToken.approve(address(fallbackContract), type(uint256).max);
    }

    /// @dev The incentive `elapsed` seconds into the auction, interpolated between the two configured bounds.
    function expectedIncentive(uint256 elapsed) internal view returns (int256) {
        int256 duration = int256(uint256(end - start));
        return INCENTIVE_AT_START + (INCENTIVE_AT_END - INCENTIVE_AT_START) * int256(elapsed) / duration;
    }

    function configId(uint64 _start, uint64 _end, int256 incentiveAtStart, int256 incentiveAtEnd)
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

/// @dev A roller that records the callback it receives from `BlueFallbackRolling` during the Midnight repayment.
contract RollerMock is IRepayCallback {
    address internal immutable FALLBACK;
    bytes32 internal immutable RETURN_VALUE;

    bool public called;
    address public callbackCaller;
    bytes32 public id;
    uint256 public units;
    address public onBehalf;
    bytes public data;

    IMidnight internal watchedMidnight;
    bytes32 internal watchedId;
    address internal watchedUser;
    uint256 public debtDuringCallback = type(uint256).max;

    constructor(address fallbackContract, bytes32 returnValue) {
        FALLBACK = fallbackContract;
        RETURN_VALUE = returnValue;
    }

    /// @dev Reads the watched debt from within the callback, to observe the state at that point of the roll.
    function watchDebt(address _midnight, bytes32 _id, address user) external {
        watchedMidnight = IMidnight(_midnight);
        watchedId = _id;
        watchedUser = user;
    }

    function rollWith(bytes memory callData) external {
        (bool success, bytes memory returnData) = FALLBACK.call(callData);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    function onRepay(bytes32 _id, Market memory, uint256 _units, address _onBehalf, bytes memory _data)
        external
        override
        returns (bytes32)
    {
        called = true;
        callbackCaller = msg.sender;
        id = _id;
        units = _units;
        onBehalf = _onBehalf;
        data = _data;
        if (address(watchedMidnight) != address(0)) {
            debtDuringCallback = watchedMidnight.debt(watchedId, watchedUser);
        }
        return RETURN_VALUE;
    }
}
