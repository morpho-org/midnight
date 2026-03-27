// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Collateral} from "../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {TakeBundler} from "../src/periphery/TakeBundler.sol";
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

        // Set trading fees to max for all breakpoints.
        midnight.setFeeRecipient(makeAddr("feeRecipient"));
        for (uint256 i; i <= 6; i++) {
            midnight.setDefaultTradingFee(address(loanToken), i, midnight.maxTradingFee(i));
        }

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken2),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        obligation.collaterals = sortCollaterals(obligation.collaterals);
        obligation.rcfThreshold = 0;

        id = midnight.touchObligation(obligation);

        offers.push();
        offers[0].buy = true;
        offers[0].maker = lender;
        offers[0].obligation = obligation;
        offers[0].expiry = block.timestamp + 200;
        offers[0].tick = MAX_TICK;

        offers.push();
        offers[1].buy = true;
        offers[1].maker = lender;
        offers[1].obligation = obligation;
        offers[1].expiry = block.timestamp + 200;
        offers[1].tick = MAX_TICK;
        offers[1].group = bytes32(uint256(1));

        deal(address(loanToken), lender, type(uint256).max);
    }

    function _authorizeBundler() internal {
        authorize(borrower, address(takeBundler));
        authorize(borrower, address(this));
    }

    function testUnauthorized() public {
        TakeBundler.Take[] memory takes = new TakeBundler.Take[](1);
        takes[0] = TakeBundler.Take({
            offer: offers[0], units: 100, sig: sig([offers[0]]), root: root([offers[0]]), proof: proof([offers[0]])
        });

        vm.prank(address(0xdead));
        vm.expectRevert("unauthorized");
        takeBundler.bundleTakeUnits(
            midnight, 100, borrower, address(0), takes, 0, type(uint256).max, 0, type(uint256).max
        );
    }

    function testBundleTakeUnits(uint256 offerUnits0, uint256 offerUnits1, uint256 units) public {
        units = bound(units, 0, uint256(type(uint128).max) * 3 / 4);
        offers[0].maxUnits = offerUnits0;
        offers[1].maxUnits = offerUnits1;
        uint256 fromOffer0 = UtilsLib.min(units, offerUnits0);

        collateralize(obligation, borrower, units);

        TakeBundler.Take[] memory takes = new TakeBundler.Take[](2);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            units: offerUnits0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            units: offerUnits1,
            sig: sig([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        if (offerUnits1 >= units - fromOffer0) {
            vm.prank(borrower);
            takeBundler.bundleTakeUnits(
                midnight, units, borrower, address(0), takes, 0, type(uint256).max, 0, type(uint256).max
            );

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(midnight.debtOf(id, borrower), units, "debt");
        } else {
            vm.prank(borrower);
            vm.expectRevert("insufficient liquidity");
            takeBundler.bundleTakeUnits(
                midnight, units, borrower, address(0), takes, 0, type(uint256).max, 0, type(uint256).max
            );
        }
    }

    function testBundleTakeBuyerAssets(uint256 offerUnits0, uint256 offerUnits1, uint256 targetBuyerAssets) public {
        targetBuyerAssets = bound(targetBuyerAssets, 1, uint256(type(uint128).max) / 2);
        offers[0].maxUnits = offerUnits0;
        offers[1].maxUnits = offerUnits1;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        // NB: splitting across offers can require 1 extra unit due to per-leg rounding of buyer assets.
        uint256 units = targetBuyerAssets.mulDivUp(WAD, price);
        uint256 fromOffer0 = UtilsLib.min(units, offerUnits0);

        collateralize(obligation, borrower, units);

        TakeBundler.Take[] memory takes = new TakeBundler.Take[](2);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            units: offerUnits0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            units: offerUnits1,
            sig: sig([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        if (offerUnits1 >= units - fromOffer0) {
            vm.prank(borrower);
            takeBundler.bundleTakeBuyerAssets(
                midnight, targetBuyerAssets, borrower, address(0), takes, 0, type(uint256).max
            );

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(loanToken.balanceOf(lender), type(uint256).max - targetBuyerAssets, "lender balance");
        } else {
            vm.prank(borrower);
            vm.expectRevert("insufficient liquidity");
            takeBundler.bundleTakeBuyerAssets(
                midnight, targetBuyerAssets, borrower, address(0), takes, 0, type(uint256).max
            );
        }
    }

    function testBundleTakeSellerAssets(uint256 offerUnits0, uint256 offerUnits1, uint256 targetSellerAssets) public {
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

        TakeBundler.Take[] memory takes = new TakeBundler.Take[](2);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            units: offerUnits0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            units: offerUnits1,
            sig: sig([offers[1]]),
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
            takeBundler.bundleTakeSellerAssets(
                midnight, targetSellerAssets, borrower, borrower, takes, 0, type(uint256).max
            );

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(loanToken.balanceOf(borrower), targetSellerAssets, "borrower balance");
        } else {
            vm.prank(borrower);
            vm.expectRevert("insufficient liquidity");
            takeBundler.bundleTakeSellerAssets(
                midnight, targetSellerAssets, borrower, borrower, takes, 0, type(uint256).max
            );
        }
    }

    // Average prices.

    function _minTick() internal view returns (uint256) {
        uint256 fee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        return TickLib.priceToTick(fee);
    }

    /// @dev Computes the expected totalBuyerAssets for bundleTakeUnits.
    /// @dev Since buy=true and the obligation starts empty, buyerPrice == tickToPrice(tick).
    function _expectedBuyerAssets(uint256 targetUnits, uint256 offerUnits0, uint256 tick0, uint256 tick1)
        internal
        pure
        returns (uint256)
    {
        uint256 fromOffer0 = UtilsLib.min(targetUnits, offerUnits0);
        uint256 fromOffer1 = targetUnits - fromOffer0;
        return
            fromOffer0.mulDivDown(TickLib.tickToPrice(tick0), WAD)
                + fromOffer1.mulDivDown(TickLib.tickToPrice(tick1), WAD);
    }

    function testAveragePriceTooHigh(
        uint256 offerUnits0,
        uint256 offerUnits1,
        uint256 targetUnits,
        uint256 tick0,
        uint256 tick1,
        uint256 maxBuyerAssets
    ) public {
        uint256 minTick = _minTick();
        tick0 = bound(tick0, minTick, MAX_TICK);
        tick1 = bound(tick1, minTick, MAX_TICK);
        // Ensure buyerAssets > 0 so the max bound actually triggers.
        uint256 minPrice = UtilsLib.min(TickLib.tickToPrice(tick0), TickLib.tickToPrice(tick1));
        targetUnits = bound(targetUnits, WAD / minPrice + 1, uint256(type(uint128).max) * 3 / 4);
        offers[0].maxUnits = offerUnits0;
        offers[0].tick = tick0;
        offers[1].maxUnits = offerUnits1;
        offers[1].tick = tick1;

        uint256 fromOffer0 = UtilsLib.min(targetUnits, offerUnits0);
        vm.assume(offerUnits1 >= targetUnits - fromOffer0);

        uint256 expected = _expectedBuyerAssets(targetUnits, offerUnits0, tick0, tick1);
        vm.assume(expected > 0);
        maxBuyerAssets = bound(maxBuyerAssets, 0, expected - 1);

        collateralize(obligation, borrower, targetUnits);

        TakeBundler.Take[] memory takes = new TakeBundler.Take[](2);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            units: offerUnits0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            units: offerUnits1,
            sig: sig([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        vm.prank(borrower);
        vm.expectRevert("buyer assets above max");
        takeBundler.bundleTakeUnits(
            midnight, targetUnits, borrower, address(0), takes, 0, maxBuyerAssets, 0, type(uint256).max
        );
    }

    function testAveragePriceTooLow(
        uint256 offerUnits0,
        uint256 offerUnits1,
        uint256 targetUnits,
        uint256 tick0,
        uint256 tick1,
        uint256 minBuyerAssets
    ) public {
        uint256 minTick = _minTick();
        tick0 = bound(tick0, minTick, MAX_TICK);
        tick1 = bound(tick1, minTick, MAX_TICK);
        targetUnits = bound(targetUnits, 1, uint256(type(uint128).max) * 3 / 4);
        offers[0].maxUnits = offerUnits0;
        offers[0].tick = tick0;
        offers[1].maxUnits = offerUnits1;
        offers[1].tick = tick1;

        uint256 fromOffer0 = UtilsLib.min(targetUnits, offerUnits0);
        vm.assume(offerUnits1 >= targetUnits - fromOffer0);

        uint256 expected = _expectedBuyerAssets(targetUnits, offerUnits0, tick0, tick1);
        minBuyerAssets = bound(minBuyerAssets, expected + 1, type(uint256).max);

        collateralize(obligation, borrower, targetUnits);

        TakeBundler.Take[] memory takes = new TakeBundler.Take[](2);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            units: offerUnits0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            units: offerUnits1,
            sig: sig([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        vm.prank(borrower);
        vm.expectRevert("buyer assets below min");
        takeBundler.bundleTakeUnits(
            midnight, targetUnits, borrower, address(0), takes, minBuyerAssets, type(uint256).max, 0, type(uint256).max
        );
    }
}
