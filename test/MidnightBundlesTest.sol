// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {WAD, ORACLE_PRICE_SCALE} from "../src/libraries/ConstantsLib.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {MidnightBundles} from "../src/periphery/MidnightBundles.sol";
import {IMidnightBundles, Take, CollateralTransfer} from "../src/periphery/interfaces/IMidnightBundles.sol";
import {BaseTest} from "./BaseTest.sol";

contract MidnightBundlesTest is BaseTest {
    using UtilsLib for uint256;

    MidnightBundles internal midnightBundles;

    Obligation internal obligation;
    bytes32 internal id;
    Offer[] internal offers;

    function setUp() public override {
        super.setUp();

        midnightBundles = new MidnightBundles();

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

        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, address(midnightBundles), true);
        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, address(this), true);
        vm.prank(lender);
        midnight.setIsAuthorized(lender, address(midnightBundles), true);
        vm.prank(lender);
        midnight.setIsAuthorized(lender, address(this), true);

        vm.prank(lender);
        loanToken.approve(address(midnightBundles), type(uint256).max);
    }

    function testUnauthorized() public {
        offers[0].buy = false;
        offers[0].maker = borrower;

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: 100,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.prank(address(0xdead));
        vm.expectRevert(IMidnightBundles.Unauthorized.selector);
        midnightBundles.unitsTargetBuyAndWithdrawCollateral(
            address(midnight), 100, 0, lender, takes, new CollateralTransfer[](0), address(0), 0, address(0)
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

        if (offerUnits1 >= units - fromOffer0) {
            vm.prank(borrower);
            midnightBundles.supplyCollateralAndUnitsTargetSell(
                address(midnight), units, 0, borrower, borrower, takes, new CollateralTransfer[](0), 0, address(0)
            );

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(midnight.debtOf(id, borrower), units, "debt");
        } else {
            vm.prank(borrower);
            vm.expectRevert(IMidnightBundles.OutOfOffers.selector);
            midnightBundles.supplyCollateralAndUnitsTargetSell(
                address(midnight), units, 0, borrower, borrower, takes, new CollateralTransfer[](0), 0, address(0)
            );
        }
    }

    function testBuyBuyerAssetsTarget(uint256 offerUnits0, uint256 offerUnits1, uint256 targetBuyerAssets) public {
        targetBuyerAssets = bound(targetBuyerAssets, 1, uint256(type(uint128).max) / 2);

        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = offerUnits0;
        offers[1].buy = false;
        offers[1].maker = borrower;
        offers[1].receiverIfMakerIsSeller = borrower;
        offers[1].maxUnits = offerUnits1;

        // Reset trading fees so buyerPrice = price <= WAD at MAX_TICK.
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        // NB: splitting across offers can require 1 extra unit due to per-leg rounding of buyer assets.
        uint256 units = targetBuyerAssets.mulDivUp(WAD, price);
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

        if (offerUnits1 >= units - fromOffer0) {
            vm.prank(lender);
            midnightBundles.assetsTargetBuyAndWithdrawCollateral(
                address(midnight),
                targetBuyerAssets,
                0,
                lender,
                takes,
                new CollateralTransfer[](0),
                address(0),
                0,
                address(0)
            );

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(loanToken.balanceOf(lender), type(uint256).max - targetBuyerAssets, "lender balance");
        } else {
            vm.prank(lender);
            vm.expectRevert(IMidnightBundles.OutOfOffers.selector);
            midnightBundles.assetsTargetBuyAndWithdrawCollateral(
                address(midnight),
                targetBuyerAssets,
                0,
                lender,
                takes,
                new CollateralTransfer[](0),
                address(0),
                0,
                address(0)
            );
        }
    }

    function testBuyUnitsTargetInconsistentObligation() public {
        Obligation memory otherObligation = obligation;
        otherObligation.maturity = block.timestamp + 360 days;

        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = 1;
        offers[1].buy = false;
        offers[1].maker = borrower;
        offers[1].receiverIfMakerIsSeller = borrower;
        offers[1].obligation = otherObligation;
        offers[1].maxUnits = 1;

        Take[] memory takes = new Take[](2);
        takes[0] = Take({
            offer: offers[0],
            units: 1,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = Take({
            offer: offers[1],
            units: 1,
            ratifierData: ratifierData([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        vm.prank(lender);
        vm.expectRevert(IMidnightBundles.InconsistentObligation.selector);
        midnightBundles.unitsTargetBuyAndWithdrawCollateral(
            address(midnight),
            2,
            type(uint256).max,
            lender,
            takes,
            new CollateralTransfer[](0),
            address(0),
            0,
            address(0)
        );
    }

    function testSellUnitsTargetInconsistentObligation() public {
        Obligation memory otherObligation = obligation;
        otherObligation.maturity = block.timestamp + 360 days;

        offers[0].maxUnits = 1;
        offers[1].obligation = otherObligation;
        offers[1].maxUnits = 1;

        Take[] memory takes = new Take[](2);
        takes[0] = Take({
            offer: offers[0],
            units: 1,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = Take({
            offer: offers[1],
            units: 1,
            ratifierData: ratifierData([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        vm.prank(borrower);
        vm.expectRevert(IMidnightBundles.InconsistentObligation.selector);
        midnightBundles.supplyCollateralAndUnitsTargetSell(
            address(midnight), 2, 0, borrower, borrower, takes, new CollateralTransfer[](0), 0, address(0)
        );
    }

    function testBuyBuyerAssetsTargetInconsistentObligation() public {
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        Obligation memory otherObligation = obligation;
        otherObligation.maturity = block.timestamp + 360 days;

        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = 1;
        offers[1].buy = false;
        offers[1].maker = borrower;
        offers[1].receiverIfMakerIsSeller = borrower;
        offers[1].obligation = otherObligation;
        offers[1].maxUnits = 1;

        Take[] memory takes = new Take[](2);
        takes[0] = Take({
            offer: offers[0],
            units: 1,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = Take({
            offer: offers[1],
            units: 1,
            ratifierData: ratifierData([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        vm.prank(lender);
        vm.expectRevert(IMidnightBundles.InconsistentObligation.selector);
        midnightBundles.assetsTargetBuyAndWithdrawCollateral(
            address(midnight), 1000, 0, lender, takes, new CollateralTransfer[](0), address(0), 0, address(0)
        );
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

        // Mirror the bundler's exact fill logic to derive units needed from offer1.
        // When offer0 fills everything, filledSellerAssets0 >= targetSellerAssets, zeroFloorSub → 0, so
        // neededFromOffer1 = 0.
        uint256 sellerPrice = price - _tradingFee;
        uint256 filledSellerAssets0 = fromOffer0.mulDivDown(sellerPrice, WAD);
        uint256 neededFromOffer1 = targetSellerAssets.zeroFloorSub(filledSellerAssets0).mulDivUp(WAD, sellerPrice);
        if (offerUnits1 >= neededFromOffer1) {
            vm.prank(borrower);
            midnightBundles.supplyCollateralAndAssetsTargetSell(
                address(midnight),
                targetSellerAssets,
                type(uint256).max,
                borrower,
                borrower,
                takes,
                new CollateralTransfer[](0),
                0,
                address(0)
            );

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(loanToken.balanceOf(borrower), targetSellerAssets, "borrower balance");
        } else {
            vm.prank(borrower);
            vm.expectRevert(IMidnightBundles.OutOfOffers.selector);
            midnightBundles.supplyCollateralAndAssetsTargetSell(
                address(midnight),
                targetSellerAssets,
                type(uint256).max,
                borrower,
                borrower,
                takes,
                new CollateralTransfer[](0),
                0,
                address(0)
            );
        }
    }

    function testSellSellerAssetsTargetInconsistentObligation() public {
        Obligation memory otherObligation = obligation;
        otherObligation.maturity = block.timestamp + 360 days;

        offers[0].maxUnits = 1;
        offers[1].obligation = otherObligation;
        offers[1].maxUnits = 1;

        Take[] memory takes = new Take[](2);
        takes[0] = Take({
            offer: offers[0],
            units: 1,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = Take({
            offer: offers[1],
            units: 1,
            ratifierData: ratifierData([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        vm.prank(borrower);
        vm.expectRevert(IMidnightBundles.InconsistentObligation.selector);
        midnightBundles.supplyCollateralAndAssetsTargetSell(
            address(midnight),
            1000,
            type(uint256).max,
            borrower,
            borrower,
            takes,
            new CollateralTransfer[](0),
            0,
            address(0)
        );
    }

    // Referral fee.

    function testBuyUnitsTargetWithReferralFee(uint256 units, uint256 referralFeePct) public {
        units = bound(units, 1, uint256(type(uint128).max) / 2);
        referralFeePct = bound(referralFeePct, 0, WAD - 1);
        address referrer = makeAddr("referrer");

        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = type(uint256).max;

        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 expectedFilledBuyerAssets = units.mulDivUp(price, WAD);
        uint256 expectedFee = expectedFilledBuyerAssets.mulDivDown(referralFeePct, WAD - referralFeePct);

        collateralize(obligation, borrower, units);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: type(uint256).max,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.prank(lender);
        midnightBundles.unitsTargetBuyAndWithdrawCollateral(
            address(midnight),
            units,
            type(uint256).max,
            lender,
            takes,
            new CollateralTransfer[](0),
            address(0),
            referralFeePct,
            referrer
        );

        assertEq(midnight.debtOf(id, borrower), units, "units filled");
        assertEq(loanToken.balanceOf(borrower), expectedFilledBuyerAssets, "maker receipt");
        assertEq(loanToken.balanceOf(referrer), expectedFee, "referrer fee");
        assertEq(
            type(uint256).max - loanToken.balanceOf(lender), expectedFilledBuyerAssets + expectedFee, "taker total cost"
        );
        assertEq(loanToken.balanceOf(address(midnightBundles)), 0, "bundler residual");
    }

    function testSellUnitsTargetWithReferralFee(uint256 units, uint256 referralFeePct) public {
        units = bound(units, 1, uint256(type(uint128).max) * 3 / 4);
        referralFeePct = bound(referralFeePct, 0, WAD - 1);
        address referrer = makeAddr("referrer");
        address receiver = makeAddr("receiver");

        offers[0].maxUnits = type(uint256).max;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        midnight.touchObligation(obligation);
        uint256 _tradingFee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 sellerPrice = price - _tradingFee;
        uint256 expectedFilledSellerAssets = units.mulDivDown(sellerPrice, WAD);
        uint256 expectedFee = expectedFilledSellerAssets.mulDivDown(referralFeePct, WAD);

        collateralize(obligation, borrower, units);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: type(uint256).max,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.prank(borrower);
        midnightBundles.supplyCollateralAndUnitsTargetSell(
            address(midnight),
            units,
            0,
            borrower,
            receiver,
            takes,
            new CollateralTransfer[](0),
            referralFeePct,
            referrer
        );

        assertEq(midnight.debtOf(id, borrower), units, "units sold");
        assertEq(loanToken.balanceOf(receiver), expectedFilledSellerAssets - expectedFee, "receiver net");
        assertEq(loanToken.balanceOf(referrer), expectedFee, "referrer fee");
        assertEq(loanToken.balanceOf(address(midnightBundles)), 0, "bundler residual");
    }

    function testBuyBuyerAssetsTargetWithReferralFee(uint256 targetBuyerAssets, uint256 referralFeePct) public {
        targetBuyerAssets = bound(targetBuyerAssets, 1, uint256(type(uint128).max) / 2);
        referralFeePct = bound(referralFeePct, 0, WAD - 1);
        address referrer = makeAddr("referrer");

        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = type(uint256).max;

        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        uint256 expectedFee = targetBuyerAssets.mulDivDown(referralFeePct, WAD);
        uint256 preFeeTarget = targetBuyerAssets - expectedFee;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 units = preFeeTarget.mulDivUp(WAD, price);

        collateralize(obligation, borrower, units);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: type(uint256).max,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.prank(lender);
        midnightBundles.assetsTargetBuyAndWithdrawCollateral(
            address(midnight),
            targetBuyerAssets,
            0,
            lender,
            takes,
            new CollateralTransfer[](0),
            address(0),
            referralFeePct,
            referrer
        );

        assertEq(type(uint256).max - loanToken.balanceOf(lender), targetBuyerAssets, "taker total cost");
        assertEq(loanToken.balanceOf(referrer), expectedFee, "referrer fee");
        assertEq(loanToken.balanceOf(borrower), preFeeTarget, "maker receipt");
        assertEq(loanToken.balanceOf(address(midnightBundles)), 0, "bundler residual");
    }

    function testSellSellerAssetsTargetWithReferralFee(uint256 targetSellerAssets, uint256 referralFeePct) public {
        // Bound such that preFeeTarget = target * WAD / (WAD - pct) stays under the uint128 unit ceiling of Midnight.
        targetSellerAssets = bound(targetSellerAssets, 1, uint256(type(uint128).max) / 4);
        referralFeePct = bound(referralFeePct, 0, WAD / 2);
        address referrer = makeAddr("referrer");
        address receiver = makeAddr("receiver");

        offers[0].maxUnits = type(uint256).max;

        uint256 expectedFee = targetSellerAssets.mulDivDown(referralFeePct, WAD - referralFeePct);
        uint256 preFeeTarget = targetSellerAssets + expectedFee;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        midnight.touchObligation(obligation);
        uint256 _tradingFee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 sellerPrice = price - _tradingFee;
        uint256 units = preFeeTarget.mulDivUp(WAD, sellerPrice);

        // Extra headroom for per-leg rounding of seller assets.
        collateralize(obligation, borrower, units + 1);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: type(uint256).max,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.prank(borrower);
        midnightBundles.supplyCollateralAndAssetsTargetSell(
            address(midnight),
            targetSellerAssets,
            type(uint256).max,
            borrower,
            receiver,
            takes,
            new CollateralTransfer[](0),
            referralFeePct,
            referrer
        );

        assertEq(loanToken.balanceOf(receiver), targetSellerAssets, "receiver net");
        assertEq(loanToken.balanceOf(referrer), expectedFee, "referrer fee");
        assertEq(loanToken.balanceOf(address(midnightBundles)), 0, "bundler residual");
    }

    function testPctExceeded() public {
        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: 1,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        offers[0].buy = false;
        Take[] memory buyTakes = new Take[](1);
        buyTakes[0] = Take({
            offer: offers[0],
            units: 1,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.startPrank(lender);
        vm.expectRevert(IMidnightBundles.PctExceeded.selector);
        midnightBundles.unitsTargetBuyAndWithdrawCollateral(
            address(midnight), 1, 0, lender, buyTakes, new CollateralTransfer[](0), address(0), WAD, address(0)
        );
        vm.expectRevert(IMidnightBundles.PctExceeded.selector);
        midnightBundles.assetsTargetBuyAndWithdrawCollateral(
            address(midnight), 1, 0, lender, buyTakes, new CollateralTransfer[](0), address(0), WAD, address(0)
        );
        vm.stopPrank();

        vm.startPrank(borrower);
        vm.expectRevert(IMidnightBundles.PctExceeded.selector);
        midnightBundles.supplyCollateralAndUnitsTargetSell(
            address(midnight), 1, 0, borrower, borrower, takes, new CollateralTransfer[](0), WAD, address(0)
        );
        vm.expectRevert(IMidnightBundles.PctExceeded.selector);
        midnightBundles.supplyCollateralAndAssetsTargetSell(
            address(midnight),
            1,
            type(uint256).max,
            borrower,
            borrower,
            takes,
            new CollateralTransfer[](0),
            WAD,
            address(0)
        );
        vm.stopPrank();
    }

    // Collateral transfers.

    function _collateralAmount(uint256 collateralIndex, uint256 debt) internal view returns (uint256) {
        uint256 oraclePrice = Oracle(obligation.collateralParams[collateralIndex].oracle).price();
        return
            debt.mulDivUp(WAD, obligation.collateralParams[collateralIndex].lltv)
                .mulDivUp(ORACLE_PRICE_SCALE, oraclePrice);
    }

    function _supplyTakerCollateral(address taker, uint256 numCollaterals, uint256 units)
        internal
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            amounts[i] = _collateralAmount(i, units / numCollaterals + 1);
            deal(obligation.collateralParams[i].token, taker, amounts[i]);
            vm.startPrank(taker);
            ERC20(obligation.collateralParams[i].token).approve(address(midnight), amounts[i]);
            midnight.supplyCollateral(obligation, i, amounts[i], taker);
            vm.stopPrank();
        }
    }

    function testBuyUnitsTargetWithCollateralWithdrawals(uint256 numCollaterals) public {
        numCollaterals = bound(numCollaterals, 0, 2);
        uint256 units = 100e18;

        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = units;

        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        collateralize(obligation, borrower, units);
        uint256[] memory amounts = _supplyTakerCollateral(lender, numCollaterals, units);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: units,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        address receiver = makeAddr("collateralReceiver");
        CollateralTransfer[] memory withdrawals = new CollateralTransfer[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            withdrawals[i] = CollateralTransfer({collateralIndex: i, assets: amounts[i] / 4});
        }

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 maxBuyerAssets = units.mulDivUp(price, WAD);

        vm.prank(lender);
        midnightBundles.unitsTargetBuyAndWithdrawCollateral(
            address(midnight), units, maxBuyerAssets, lender, takes, withdrawals, receiver, 0, address(0)
        );

        for (uint256 i; i < numCollaterals; i++) {
            assertEq(midnight.collateral(id, lender, i), amounts[i] - amounts[i] / 4);
            assertEq(ERC20(obligation.collateralParams[i].token).balanceOf(receiver), amounts[i] / 4);
        }
    }

    function testBuyBuyerAssetsTargetWithCollateralWithdrawals(uint256 numCollaterals) public {
        numCollaterals = bound(numCollaterals, 0, 2);
        uint256 units = 100e18;

        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = units;

        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        collateralize(obligation, borrower, units);
        uint256[] memory amounts = _supplyTakerCollateral(lender, numCollaterals, units);

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

        address receiver = makeAddr("collateralReceiver");
        CollateralTransfer[] memory withdrawals = new CollateralTransfer[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            withdrawals[i] = CollateralTransfer({collateralIndex: i, assets: amounts[i] / 4});
        }

        vm.prank(lender);
        midnightBundles.assetsTargetBuyAndWithdrawCollateral(
            address(midnight), targetBuyerAssets, 0, lender, takes, withdrawals, receiver, 0, address(0)
        );

        for (uint256 i; i < numCollaterals; i++) {
            assertEq(midnight.collateral(id, lender, i), amounts[i] - amounts[i] / 4);
            assertEq(ERC20(obligation.collateralParams[i].token).balanceOf(receiver), amounts[i] / 4);
        }
    }

    function testSellUnitsTargetWithCollateralSupplies(uint256 numCollaterals) public {
        numCollaterals = bound(numCollaterals, 1, 2);
        uint256 units = 100e18;

        offers[0].maxUnits = units;

        CollateralTransfer[] memory supplies = new CollateralTransfer[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            uint256 amount = _collateralAmount(i, units / numCollaterals + 1);
            deal(obligation.collateralParams[i].token, borrower, amount);
            vm.prank(borrower);
            ERC20(obligation.collateralParams[i].token).approve(address(midnightBundles), amount);
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
        midnightBundles.supplyCollateralAndUnitsTargetSell(
            address(midnight), units, 0, borrower, borrower, takes, supplies, 0, address(0)
        );

        for (uint256 i; i < numCollaterals; i++) {
            assertEq(midnight.collateral(id, borrower, i), supplies[i].assets);
        }
        assertEq(midnight.debtOf(id, borrower), units);
    }

    function testRepay(uint256 units, uint256 repayUnits, uint256 withdrawAssets) public {
        units = bound(units, 1, uint256(type(uint128).max) * 3 / 4);
        repayUnits = bound(repayUnits, 0, units);

        offers[0].maxUnits = units;

        // Zero trading fees so the borrower receives exactly `units` loan tokens for the sale,
        // covering any `repayUnits <= units`.
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        // Borrower sells units to get loan token + accumulate debt and collateral on Midnight.
        Take[] memory sellTakes = new Take[](1);
        sellTakes[0] = Take({
            offer: offers[0],
            units: units,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        collateralize(obligation, borrower, units);
        uint256 collateralAmount = midnight.collateral(id, borrower, 0);
        vm.prank(borrower);
        midnightBundles.supplyCollateralAndUnitsTargetSell(
            address(midnight), units, 0, borrower, borrower, sellTakes, new CollateralTransfer[](0), 0, address(0)
        );

        uint256 maxWithdrawable = collateralAmount - _collateralAmount(0, units - repayUnits);
        withdrawAssets = bound(withdrawAssets, 0, maxWithdrawable);
        address collateralReceiver = makeAddr("collateralReceiver");

        vm.prank(borrower);
        loanToken.approve(address(midnightBundles), repayUnits);

        CollateralTransfer[] memory withdrawals = new CollateralTransfer[](1);
        withdrawals[0] = CollateralTransfer({collateralIndex: 0, assets: withdrawAssets});

        uint256 borrowerLoanBalanceBefore = loanToken.balanceOf(borrower);

        vm.prank(borrower);
        midnightBundles.repayAndWithdrawCollateral(
            address(midnight), obligation, repayUnits, borrower, withdrawals, collateralReceiver
        );

        assertEq(midnight.debtOf(id, borrower), units - repayUnits, "debt");
        assertEq(midnight.collateral(id, borrower, 0), collateralAmount - withdrawAssets, "remaining collateral");
        assertEq(
            ERC20(obligation.collateralParams[0].token).balanceOf(collateralReceiver),
            withdrawAssets,
            "collateral receiver"
        );
        assertEq(loanToken.balanceOf(borrower), borrowerLoanBalanceBefore - repayUnits, "borrower loan balance");
        assertEq(loanToken.balanceOf(address(midnightBundles)), 0, "bundler residual");
    }

    function testSellSellerAssetsTargetWithCollateralSupplies(uint256 numCollaterals) public {
        deal(address(loanToken), address(midnightBundles), 0);
        numCollaterals = bound(numCollaterals, 1, 2);
        uint256 units = 100e18;

        offers[0].maxUnits = units;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        midnight.touchObligation(obligation);
        uint256 _tradingFee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 sellerPrice = price - _tradingFee;
        uint256 targetSellerAssets = units.mulDivDown(sellerPrice, WAD);

        CollateralTransfer[] memory supplies = new CollateralTransfer[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            uint256 amount = _collateralAmount(i, units / numCollaterals + 1);
            deal(obligation.collateralParams[i].token, borrower, amount);
            vm.prank(borrower);
            ERC20(obligation.collateralParams[i].token).approve(address(midnightBundles), amount);
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
        midnightBundles.supplyCollateralAndAssetsTargetSell(
            address(midnight), targetSellerAssets, type(uint256).max, borrower, borrower, takes, supplies, 0, address(0)
        );

        for (uint256 i; i < numCollaterals; i++) {
            assertEq(midnight.collateral(id, borrower, i), supplies[i].assets);
        }
        assertEq(loanToken.balanceOf(borrower), targetSellerAssets);
    }

    // Average price.

    function testBuyUnitsTargetAveragePriceExceeded(uint256 tick) public {
        tick = bound(tick, 1, MAX_TICK);
        uint256 units = 100e18;

        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = units;
        offers[0].tick = tick;
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }
        uint256 price = TickLib.tickToPrice(tick);

        collateralize(obligation, borrower, units);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: units,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.prank(lender);
        vm.expectRevert();
        midnightBundles.unitsTargetBuyAndWithdrawCollateral(
            address(midnight), units, price - 1, lender, takes, new CollateralTransfer[](0), address(0), 0, address(0)
        );
    }

    function testSellUnitsTargetAveragePriceTooLow(uint256 tick) public {
        tick = bound(tick, 1, MAX_TICK);
        uint256 units = 100e18;

        offers[0].maxUnits = units;
        offers[0].tick = tick;
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }
        uint256 price = TickLib.tickToPrice(tick);

        collateralize(obligation, borrower, units);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: units,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        uint256 minSellerAssets = units.mulDivDown(price, WAD) + 1;
        vm.prank(borrower);
        vm.expectRevert(IMidnightBundles.SellerAssetsTooLow.selector);
        midnightBundles.supplyCollateralAndUnitsTargetSell(
            address(midnight),
            units,
            minSellerAssets,
            borrower,
            borrower,
            takes,
            new CollateralTransfer[](0),
            0,
            address(0)
        );
    }

    function testBuyBuyerAssetsTargetAveragePriceExceeded(uint256 tick) public {
        tick = bound(tick, 1, MAX_TICK);
        uint256 units = 100e18;

        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = units;
        offers[0].tick = tick;
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }
        uint256 price = TickLib.tickToPrice(tick);

        collateralize(obligation, borrower, units);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: units,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.prank(lender);
        vm.expectRevert(IMidnightBundles.UnitsTooLow.selector);
        midnightBundles.assetsTargetBuyAndWithdrawCollateral(
            address(midnight),
            units.mulDivUp(price, WAD),
            units + 2,
            lender,
            takes,
            new CollateralTransfer[](0),
            address(0),
            0,
            address(0)
        );
    }

    function testSellSellerAssetsTargetAveragePriceTooLow(uint256 tick) public {
        tick = bound(tick, 1, MAX_TICK);
        uint256 units = 100e18;

        offers[0].maxUnits = units;
        offers[0].tick = tick;
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }
        uint256 price = TickLib.tickToPrice(tick);
        uint256 targetSellerAssets = units.mulDivDown(price, WAD);

        collateralize(obligation, borrower, units);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({
            offer: offers[0],
            units: units,
            ratifierData: ratifierData([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.prank(borrower);
        vm.expectRevert(IMidnightBundles.UnitsTooHigh.selector);
        midnightBundles.supplyCollateralAndAssetsTargetSell(
            address(midnight),
            targetSellerAssets,
            price + 1,
            borrower,
            borrower,
            takes,
            new CollateralTransfer[](0),
            0,
            address(0)
        );
    }
}
