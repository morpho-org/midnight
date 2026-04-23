// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {WAD, ORACLE_PRICE_SCALE} from "../src/libraries/ConstantsLib.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {TakeBundler} from "../src/periphery/TakeBundler.sol";
import {ITakeBundler, Take, CollateralTransfer} from "../src/periphery/interfaces/ITakeBundler.sol";
import {BaseTest} from "./BaseTest.sol";

contract BundlerTest is BaseTest {
    using UtilsLib for uint256;

    TakeBundler internal takeBundler;

    Obligation internal obligation;
    bytes32 internal id;
    Offer[] internal offers;

    function setUp() public override {
        super.setUp();

        takeBundler = new TakeBundler();
        deal(address(loanToken), address(takeBundler), type(uint256).max);
        vm.prank(address(takeBundler));
        loanToken.approve(address(midnight), type(uint256).max);

        // Set trading fees to max for all breakpoints.
        midnight.setFeeClaimer(makeAddr("feeClaimer"));
        for (uint256 i; i <= 6; i++) {
            midnight.setDefaultTradingFee(address(loanToken), i, midnight.maxTradingFee(i));
        }

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        obligation.collateralParams = sortCollateralParams(obligation.collateralParams);
        obligation.rcfThreshold = 0;

        id = midnight.touchObligation(obligation);

        offers.push();
        offers[0].buy = true;
        offers[0].maker = lender;
        offers[0].obligation = obligation;
        offers[0].ratifier = address(ecrecoverRatifier);
        offers[0].expiry = block.timestamp + 200;
        offers[0].tick = MAX_TICK;

        offers.push();
        offers[1].buy = true;
        offers[1].maker = lender;
        offers[1].obligation = obligation;
        offers[1].ratifier = address(ecrecoverRatifier);
        offers[1].expiry = block.timestamp + 200;
        offers[1].tick = MAX_TICK;
        offers[1].group = bytes32(uint256(1));

        deal(address(loanToken), lender, type(uint256).max);
    }

    function _authorizeBundler() internal {
        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, address(takeBundler), true);
        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, address(this), true);
    }

    function testUnauthorized() public {
        offers[0].buy = false;

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: 100,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.prank(address(0xdead));
        vm.expectRevert(ITakeBundler.Unauthorized.selector);
        takeBundler.buyUnitsTarget(
            address(midnight), 100, borrower, takes, type(uint256).max, new CollateralTransfer[](0), address(0)
        );
    }

    function testSellUnitsTarget(uint256 offerUnits0, uint256 offerUnits1, uint256 units) public {
        units = bound(units, 0, uint256(type(uint128).max) * 3 / 4);
        offers[0].maxUnits = offerUnits0;
        offers[1].maxUnits = offerUnits1;
        uint256 fromOffer0 = UtilsLib.min(units, offerUnits0);

        collateralize(obligation, borrower, units);

        Take[] memory takes = new Take[](2);
        takes[0] = Take({
            offer: offers[0],
            units: offerUnits0,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = Take({
            offer: offers[1],
            units: offerUnits1,
            ratifierData: ratifierData([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        if (offerUnits1 >= units - fromOffer0) {
            vm.prank(borrower);
            takeBundler.sellUnitsTarget(
                address(midnight), units, borrower, borrower, takes, 0, new CollateralTransfer[](0)
            );

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(midnight.debtOf(id, borrower), units, "debt");
        } else {
            vm.prank(borrower);
            vm.expectRevert(ITakeBundler.InsufficientLiquidity.selector);
            takeBundler.sellUnitsTarget(
                address(midnight), units, borrower, borrower, takes, 0, new CollateralTransfer[](0)
            );
        }
    }

    function testBuyBuyerAssetsTarget(uint256 offerUnits0, uint256 offerUnits1, uint256 targetBuyerAssets) public {
        targetBuyerAssets = bound(targetBuyerAssets, 1, uint256(type(uint128).max) / 2);

        offers[0].buy = false;
        offers[0].receiverIfMakerIsSeller = lender;
        offers[0].maxUnits = offerUnits0;
        offers[1].buy = false;
        offers[1].receiverIfMakerIsSeller = lender;
        offers[1].maxUnits = offerUnits1;

        // Reset trading fees so buyerPrice = price <= WAD at MAX_TICK.
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }
        deal(address(loanToken), lender, 0);

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        // NB: splitting across offers can require 1 extra unit due to per-leg rounding of buyer assets.
        uint256 units = targetBuyerAssets.mulDivUp(WAD, price);
        uint256 fromOffer0 = UtilsLib.min(units, offerUnits0);

        collateralize(obligation, lender, units);

        Take[] memory takes = new Take[](2);
        takes[0] = Take({
            offer: offers[0],
            units: offerUnits0,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = Take({
            offer: offers[1],
            units: offerUnits1,
            ratifierData: ratifierData([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        if (offerUnits1 >= units - fromOffer0) {
            vm.prank(borrower);
            takeBundler.buyBuyerAssetsTarget(
                address(midnight),
                targetBuyerAssets,
                borrower,
                takes,
                0,
                type(uint256).max,
                new CollateralTransfer[](0),
                address(0)
            );

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, lender), "total consumed");
            assertEq(
                loanToken.balanceOf(address(takeBundler)), type(uint256).max - targetBuyerAssets, "bundler balance"
            );
        } else {
            vm.prank(borrower);
            vm.expectRevert(ITakeBundler.InsufficientLiquidity.selector);
            takeBundler.buyBuyerAssetsTarget(
                address(midnight),
                targetBuyerAssets,
                borrower,
                takes,
                0,
                type(uint256).max,
                new CollateralTransfer[](0),
                address(0)
            );
        }
    }

    function testSellSellerAssetsTarget(uint256 offerUnits0, uint256 offerUnits1, uint256 targetSellerAssets) public {
        targetSellerAssets = bound(targetSellerAssets, 1, uint256(type(uint128).max) / 2);
        offers[0].maxUnits = offerUnits0;
        offers[1].maxUnits = offerUnits1;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        midnight.touchObligation(obligation);
        uint256 _tradingFee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 units = targetSellerAssets.mulDivUp(WAD, price - _tradingFee);
        uint256 fromOffer0 = UtilsLib.min(units, offerUnits0);

        // Extra collateral headroom for the potential extra unit of debt.
        collateralize(obligation, borrower, units + 1);

        Take[] memory takes = new Take[](2);
        takes[0] = Take({
            offer: offers[0],
            units: offerUnits0,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = Take({
            offer: offers[1],
            units: offerUnits1,
            ratifierData: ratifierData([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        // Mirror the bundler's exact fill logic to derive units needed from offer1.
        // When offer0 fills everything, filledSellerAssets0 >= targetSellerAssets, zeroFloorSub → 0, so
        // neededFromOffer1 = 0.
        uint256 sellerPrice = price - _tradingFee;
        uint256 filledSellerAssets0 = fromOffer0.mulDivDown(sellerPrice, WAD);
        uint256 neededFromOffer1 = targetSellerAssets.zeroFloorSub(filledSellerAssets0).mulDivUp(WAD, sellerPrice);
        if (offerUnits1 >= neededFromOffer1) {
            vm.prank(borrower);
            takeBundler.sellSellerAssetsTarget(
                address(midnight),
                targetSellerAssets,
                borrower,
                borrower,
                takes,
                0,
                type(uint256).max,
                new CollateralTransfer[](0)
            );

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(loanToken.balanceOf(borrower), targetSellerAssets, "borrower balance");
        } else {
            vm.prank(borrower);
            vm.expectRevert(ITakeBundler.InsufficientLiquidity.selector);
            takeBundler.sellSellerAssetsTarget(
                address(midnight),
                targetSellerAssets,
                borrower,
                borrower,
                takes,
                0,
                type(uint256).max,
                new CollateralTransfer[](0)
            );
        }
    }

    // Collateral transfers.

    function _collateralAmount(uint256 collateralIndex, uint256 debt) internal view returns (uint256) {
        uint256 oraclePrice = Oracle(obligation.collateralParams[collateralIndex].oracle).price();
        return
            debt.mulDivUp(WAD, obligation.collateralParams[collateralIndex].lltv)
                .mulDivUp(ORACLE_PRICE_SCALE, oraclePrice);
    }

    function _supplyBorrowerCollateral(uint256 numCollaterals, uint256 units)
        internal
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            amounts[i] = _collateralAmount(i, units / numCollaterals + 1);
            deal(obligation.collateralParams[i].token, borrower, amounts[i]);
            vm.startPrank(borrower);
            ERC20(obligation.collateralParams[i].token).approve(address(midnight), amounts[i]);
            midnight.supplyCollateral(obligation, i, amounts[i], borrower);
            vm.stopPrank();
        }
    }

    function testBuyUnitsTargetWithCollateralWithdrawals(uint256 numCollaterals) public {
        numCollaterals = bound(numCollaterals, 0, 2);
        uint256 units = 100e18;

        offers[0].buy = false;
        offers[0].receiverIfMakerIsSeller = lender;
        offers[0].maxUnits = units;

        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }
        deal(address(loanToken), lender, 0);

        collateralize(obligation, lender, units);
        uint256[] memory amounts = _supplyBorrowerCollateral(numCollaterals, units);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: units,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        _authorizeBundler();

        address receiver = makeAddr("collateralReceiver");
        CollateralTransfer[] memory withdrawals = new CollateralTransfer[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            withdrawals[i] = CollateralTransfer({collateralIndex: i, assets: amounts[i] / 4});
        }

        vm.prank(borrower);
        takeBundler.buyUnitsTarget(address(midnight), units, borrower, takes, type(uint256).max, withdrawals, receiver);

        for (uint256 i; i < numCollaterals; i++) {
            assertEq(midnight.collateral(id, borrower, i), amounts[i] - amounts[i] / 4);
            assertEq(ERC20(obligation.collateralParams[i].token).balanceOf(receiver), amounts[i] / 4);
        }
    }

    function testBuyBuyerAssetsTargetWithCollateralWithdrawals(uint256 numCollaterals) public {
        numCollaterals = bound(numCollaterals, 0, 2);
        uint256 units = 100e18;

        offers[0].buy = false;
        offers[0].receiverIfMakerIsSeller = lender;
        offers[0].maxUnits = units;

        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }
        deal(address(loanToken), lender, 0);

        collateralize(obligation, lender, units);
        uint256[] memory amounts = _supplyBorrowerCollateral(numCollaterals, units);

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 targetBuyerAssets = units.mulDivUp(price, WAD);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: units,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        _authorizeBundler();

        address receiver = makeAddr("collateralReceiver");
        CollateralTransfer[] memory withdrawals = new CollateralTransfer[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            withdrawals[i] = CollateralTransfer({collateralIndex: i, assets: amounts[i] / 4});
        }

        vm.prank(borrower);
        takeBundler.buyBuyerAssetsTarget(
            address(midnight), targetBuyerAssets, borrower, takes, 0, type(uint256).max, withdrawals, receiver
        );

        for (uint256 i; i < numCollaterals; i++) {
            assertEq(midnight.collateral(id, borrower, i), amounts[i] - amounts[i] / 4);
            assertEq(ERC20(obligation.collateralParams[i].token).balanceOf(receiver), amounts[i] / 4);
        }
    }

    function testSellUnitsTargetWithCollateralSupplies(uint256 numCollaterals) public {
        numCollaterals = bound(numCollaterals, 1, 2);
        uint256 units = 100e18;

        offers[0].maxUnits = units;

        _authorizeBundler();

        CollateralTransfer[] memory supplies = new CollateralTransfer[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            uint256 amount = _collateralAmount(i, units / numCollaterals + 1);
            deal(obligation.collateralParams[i].token, borrower, amount);
            vm.prank(borrower);
            ERC20(obligation.collateralParams[i].token).approve(address(takeBundler), amount);
            supplies[i] = CollateralTransfer({collateralIndex: i, assets: amount});
        }

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: units,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.prank(borrower);
        takeBundler.sellUnitsTarget(address(midnight), units, borrower, borrower, takes, 0, supplies);

        for (uint256 i; i < numCollaterals; i++) {
            assertEq(midnight.collateral(id, borrower, i), supplies[i].assets);
        }
        assertEq(midnight.debtOf(id, borrower), units);
    }

    function testSellSellerAssetsTargetWithCollateralSupplies(uint256 numCollaterals) public {
        numCollaterals = bound(numCollaterals, 1, 2);
        uint256 units = 100e18;

        offers[0].maxUnits = units;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        midnight.touchObligation(obligation);
        uint256 _tradingFee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 sellerPrice = price - _tradingFee;
        uint256 targetSellerAssets = units.mulDivDown(sellerPrice, WAD);

        _authorizeBundler();

        CollateralTransfer[] memory supplies = new CollateralTransfer[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            uint256 amount = _collateralAmount(i, units / numCollaterals + 1);
            deal(obligation.collateralParams[i].token, borrower, amount);
            vm.prank(borrower);
            ERC20(obligation.collateralParams[i].token).approve(address(takeBundler), amount);
            supplies[i] = CollateralTransfer({collateralIndex: i, assets: amount});
        }

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: units,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.prank(borrower);
        takeBundler.sellSellerAssetsTarget(
            address(midnight), targetSellerAssets, borrower, borrower, takes, 0, type(uint256).max, supplies
        );

        for (uint256 i; i < numCollaterals; i++) {
            assertEq(midnight.collateral(id, borrower, i), supplies[i].assets);
        }
        assertEq(loanToken.balanceOf(borrower), targetSellerAssets);
    }

    // Average prices.

    /// @dev Computes the expected totalBuyerAssets for buyUnitsTarget.
    /// @dev Since buy=false, buyerPrice == tickToPrice(tick) + tradingFee.
    function _expectedBuyerAssets(uint256 targetUnits, uint256 offerUnits0, uint256 tick0, uint256 tick1)
        internal
        view
        returns (uint256)
    {
        uint256 fee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 fromOffer0 = UtilsLib.min(targetUnits, offerUnits0);
        uint256 fromOffer1 = targetUnits - fromOffer0;
        return fromOffer0.mulDivUp(TickLib.tickToPrice(tick0) + fee, WAD)
            + fromOffer1.mulDivUp(TickLib.tickToPrice(tick1) + fee, WAD);
    }

    /// @dev Computes the expected totalSellerAssets for sellUnitsTarget.
    /// @dev Since buy=true, sellerPrice == tickToPrice(tick) - tradingFee.
    function _expectedSellerAssets(uint256 targetUnits, uint256 offerUnits0, uint256 tick0, uint256 tick1)
        internal
        view
        returns (uint256)
    {
        uint256 fee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 fromOffer0 = UtilsLib.min(targetUnits, offerUnits0);
        uint256 fromOffer1 = targetUnits - fromOffer0;
        return fromOffer0.mulDivDown(TickLib.tickToPrice(tick0) - fee, WAD)
            + fromOffer1.mulDivDown(TickLib.tickToPrice(tick1) - fee, WAD);
    }

    function testAveragePriceTooHigh(
        uint256 offerUnits0,
        uint256 offerUnits1,
        uint256 targetUnits,
        uint256 tick0,
        uint256 tick1,
        uint256 maxBuyerAssets
    ) public {
        tick0 = bound(tick0, 0, MAX_TICK);
        tick1 = bound(tick1, 0, MAX_TICK);
        // Ensure buyerAssets > 0 so the max bound actually triggers.
        uint256 fee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 minBuyerPrice = UtilsLib.min(TickLib.tickToPrice(tick0) + fee, TickLib.tickToPrice(tick1) + fee);
        targetUnits = bound(targetUnits, WAD / minBuyerPrice + 1, uint256(type(uint128).max) * 3 / 4);

        offers[0].buy = false;
        offers[0].receiverIfMakerIsSeller = lender;
        offers[0].maxUnits = offerUnits0;
        offers[0].tick = tick0;
        offers[1].buy = false;
        offers[1].receiverIfMakerIsSeller = lender;
        offers[1].maxUnits = offerUnits1;
        offers[1].tick = tick1;
        deal(address(loanToken), lender, 0);

        uint256 fromOffer0 = UtilsLib.min(targetUnits, offerUnits0);
        vm.assume(offerUnits1 >= targetUnits - fromOffer0);

        uint256 expected = _expectedBuyerAssets(targetUnits, offerUnits0, tick0, tick1);
        vm.assume(expected > 0);
        maxBuyerAssets = bound(maxBuyerAssets, 0, expected - 1);

        collateralize(obligation, lender, targetUnits);

        Take[] memory takes = new Take[](2);
        takes[0] = Take({
            offer: offers[0],
            units: offerUnits0,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = Take({
            offer: offers[1],
            units: offerUnits1,
            ratifierData: ratifierData([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        vm.prank(borrower);
        vm.expectRevert(ITakeBundler.BuyerAssetsAboveMax.selector);
        takeBundler.buyUnitsTarget(
            address(midnight), targetUnits, borrower, takes, maxBuyerAssets, new CollateralTransfer[](0), address(0)
        );
    }

    function testAveragePriceTooLow(
        uint256 offerUnits0,
        uint256 offerUnits1,
        uint256 targetUnits,
        uint256 tick0,
        uint256 tick1,
        uint256 minSellerAssets
    ) public {
        // Ensure sellerPrice > 0 so the min bound actually triggers.
        uint256 fee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 minTick = TickLib.priceToTick(fee + 1);
        tick0 = bound(tick0, minTick, MAX_TICK);
        tick1 = bound(tick1, minTick, MAX_TICK);
        uint256 minSellerPrice = UtilsLib.min(TickLib.tickToPrice(tick0) - fee, TickLib.tickToPrice(tick1) - fee);
        targetUnits = bound(targetUnits, WAD / minSellerPrice + 1, uint256(type(uint128).max) * 3 / 4);

        offers[0].maxUnits = offerUnits0;
        offers[0].tick = tick0;
        offers[1].maxUnits = offerUnits1;
        offers[1].tick = tick1;

        uint256 fromOffer0 = UtilsLib.min(targetUnits, offerUnits0);
        vm.assume(offerUnits1 >= targetUnits - fromOffer0);

        uint256 expected = _expectedSellerAssets(targetUnits, offerUnits0, tick0, tick1);
        vm.assume(expected > 0);
        minSellerAssets = bound(minSellerAssets, expected + 1, type(uint256).max);

        collateralize(obligation, borrower, targetUnits);

        Take[] memory takes = new Take[](2);
        takes[0] = Take({
            offer: offers[0],
            units: offerUnits0,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = Take({
            offer: offers[1],
            units: offerUnits1,
            ratifierData: ratifierData([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        vm.prank(borrower);
        vm.expectRevert(ITakeBundler.SellerAssetsBelowMin.selector);
        takeBundler.sellUnitsTarget(
            address(midnight), targetUnits, borrower, borrower, takes, minSellerAssets, new CollateralTransfer[](0)
        );
    }
}
