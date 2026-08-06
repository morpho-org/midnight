// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IMorpho, Id, MarketParams} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IMidnight, Market, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {BlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/BlueFallbackRolling.sol";
import {IBlueFallbackRolling} from "../src/periphery/blue-fallback-rolling/IBlueFallbackRolling.sol";
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
    uint64 internal start;

    function setUp() public override {
        super.setUp();
        start = uint64(vm.getBlockTimestamp());

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

        // The Midnight market must be final before the rolling contract is deployed, since its id is immutable.
        fallbackContract = newFallbackContract(blueMarketParams, start, INCENTIVE);

        collateralize(midnightMarket, borrower, DEBT, blueCollateralIndex);
        setupMarket(midnightMarket, DEBT);

        deal(address(loanToken), address(this), 2 * DEBT);
        loanToken.approve(address(blue), type(uint256).max);
        blue.supply(blueMarketParams, 2 * DEBT, 0, lender, hex"");
    }

    /// @dev Deploys a rolling contract for the current Midnight market and authorizes it for the borrower.
    function newFallbackContract(MarketParams memory _blueMarketParams, uint64 _start, uint64 _incentive)
        internal
        returns (BlueFallbackRolling)
    {
        BlueFallbackRolling newContract = new BlueFallbackRolling(
            address(midnight),
            address(blue),
            toId(midnightMarket),
            Id.unwrap(_blueMarketParams.id()),
            _start,
            _incentive
        );

        vm.prank(borrower);
        midnight.setIsAuthorized(address(newContract), true, borrower);
        vm.prank(borrower);
        blue.setAuthorization(address(newContract), true);

        return newContract;
    }

    function testAnyoneCanRollBorrowerToBlue() public {
        uint256 midnightCollateral = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);

        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, DEBT);

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
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, debtAssets);

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

    function testCannotRollBeforeStart() public {
        uint64 futureStart = uint64(vm.getBlockTimestamp() + 1);
        BlueFallbackRolling futureContract = newFallbackContract(blueMarketParams, futureStart, INCENTIVE);

        vm.expectRevert(IBlueFallbackRolling.NotStarted.selector);
        vm.prank(keeper);
        futureContract.roll(midnightMarket, blueMarketParams, borrower, DEBT);
    }

    function testRollRevertsForOtherBlueMarket() public {
        blueMarketParams.oracle = makeAddr("otherOracle");

        vm.expectRevert(IBlueFallbackRolling.InconsistentBlueMarket.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, DEBT);
    }

    function testRollRevertsForOtherMidnightMarket() public {
        midnightMarket.maturity += 1;

        vm.expectRevert(IBlueFallbackRolling.InconsistentMidnightMarket.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, DEBT);
    }

    function testRollRevertsForInconsistentLoanToken() public {
        // The Blue market of the config has a loan token that differs from the Midnight one.
        MarketParams memory otherBlueMarketParams = blueMarketParams;
        otherBlueMarketParams.loanToken = makeAddr("otherLoanToken");
        BlueFallbackRolling otherContract = newFallbackContract(otherBlueMarketParams, start, INCENTIVE);

        vm.expectRevert(IBlueFallbackRolling.InconsistentLoanToken.selector);
        vm.prank(keeper);
        otherContract.roll(midnightMarket, otherBlueMarketParams, borrower, DEBT);
    }

    function testRollRevertsForMultipleActivatedCollaterals() public {
        collateralize(midnightMarket, borrower, DEBT, 1 - blueCollateralIndex);

        vm.expectRevert(IBlueFallbackRolling.IncorrectActivatedCollateral.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, DEBT);
    }

    function testRollRevertsWhenActivatedCollateralDoesNotMatchBlue() public {
        uint256 otherCollateralIndex = 1 - blueCollateralIndex;
        collateralize(midnightMarket, borrower, DEBT, otherCollateralIndex);
        uint256 blueCollateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.prank(borrower);
        midnight.withdrawCollateral(midnightMarket, blueCollateralIndex, blueCollateralAssets, borrower, borrower);

        vm.expectRevert(IBlueFallbackRolling.InconsistentCollateralToken.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, DEBT);
    }

    function testSupplyCollateralCallbackRevertsIfCallerIsNotBlue() public {
        uint256 collateralAssets = midnight.collateral(toId(midnightMarket), borrower, blueCollateralIndex);
        vm.expectRevert(IBlueFallbackRolling.NotBlue.selector);
        fallbackContract.onMorphoSupplyCollateral(
            collateralAssets,
            abi.encode(midnightMarket, blueMarketParams, blueCollateralIndex, DEBT, DEBT * INCENTIVE / WAD, borrower)
        );
    }

    function testConstructor() public view {
        assertEq(fallbackContract.MIDNIGHT(), address(midnight));
        assertEq(fallbackContract.BLUE(), address(blue));
        assertEq(fallbackContract.MIDNIGHT_ID(), toId(midnightMarket));
        assertEq(fallbackContract.BLUE_ID(), Id.unwrap(blueMarketParams.id()));
        assertEq(fallbackContract.START(), start);
        assertEq(fallbackContract.INCENTIVE(), INCENTIVE);
    }

    function testConstructorRevertsForTooLargeIncentive() public {
        vm.expectRevert(IBlueFallbackRolling.IncentiveTooHigh.selector);
        new BlueFallbackRolling(
            address(midnight),
            address(blue),
            toId(midnightMarket),
            Id.unwrap(blueMarketParams.id()),
            start,
            MAX_INCENTIVE + 1
        );
    }

    function testConstructorAllowsOneIncentive() public {
        BlueFallbackRolling maxIncentiveContract = newFallbackContract(blueMarketParams, start, MAX_INCENTIVE);

        assertEq(maxIncentiveContract.INCENTIVE(), MAX_INCENTIVE);
    }

    function testRollRevertsWithoutBlueAuthorization() public {
        vm.prank(borrower);
        blue.setAuthorization(address(fallbackContract), false);

        vm.expectRevert(bytes("unauthorized"));
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, DEBT);
    }

    function testRollRevertsWithoutMidnightAuthorization() public {
        vm.prank(borrower);
        midnight.setIsAuthorized(address(fallbackContract), false, borrower);

        vm.expectRevert(IMidnight.Unauthorized.selector);
        vm.prank(keeper);
        fallbackContract.roll(midnightMarket, blueMarketParams, borrower, DEBT);
    }
}
