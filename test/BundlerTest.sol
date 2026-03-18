// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Collateral} from "../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {WAD, BALANCE_DECIMALS} from "../src/libraries/ConstantsLib.sol";
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
        midnight.setTradingFeeRecipient(makeAddr("feeRecipient"));
        for (uint256 i; i <= 6; i++) {
            midnight.setDefaultTradingFee(address(loanToken), i, midnight.maxTradingFee(i));
        }

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken1),
                    lltv: 0.75e18,
                    maxLif: maxLif(0.75e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.collaterals
            .push(
                Collateral({
                    token: address(collateralToken2),
                    lltv: 0.75e18,
                    maxLif: maxLif(0.75e18, 0.25e18),
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
            offer: offers[0],
            obligationUnits: 100,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.prank(address(0xdead));
        vm.expectRevert("unauthorized");
        takeBundler.bundleTakeUnits(
            midnight, 100, borrower, address(0), takes, 0, type(uint256).max, 0, type(uint256).max
        );
    }

    function testBundleTakeUnits(uint256 offerUnits0, uint256 offerUnits1, uint256 units) public {
        units = bound(units, 0, uint256(type(uint128).max) * 3 / 4);
        offers[0].obligationUnits = offerUnits0;
        offers[1].obligationUnits = offerUnits1;
        uint256 fromOffer0 = UtilsLib.min(units, offerUnits0);

        collateralize(obligation, borrower, units);

        TakeBundler.Take[] memory takes = new TakeBundler.Take[](2);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            obligationUnits: offerUnits0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            obligationUnits: offerUnits1,
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
        targetBuyerAssets = bound(targetBuyerAssets, 1, uint256(type(uint128).max) / (2 * BALANCE_DECIMALS));
        offers[0].obligationUnits = offerUnits0;
        offers[1].obligationUnits = offerUnits1;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        // NB: splitting across 2 offers can add up to BALANCE_DECIMALS - 1 extra units due to per-leg rounding.
        uint256 units = targetBuyerAssets.mulDivUp(WAD, price).mulDivUp(BALANCE_DECIMALS, 1);
        uint256 fromOffer0 = UtilsLib.min(units, offerUnits0);

        // Provide collateral buffer for potential extra units from 2-leg rounding.
        collateralize(obligation, borrower, units + BALANCE_DECIMALS);

        TakeBundler.Take[] memory takes = new TakeBundler.Take[](2);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            obligationUnits: offerUnits0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            obligationUnits: offerUnits1,
            sig: sig([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        if (fromOffer0 >= units || offerUnits1 >= units + BALANCE_DECIMALS - fromOffer0) {
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
        targetSellerAssets = bound(targetSellerAssets, 1, uint256(type(uint128).max) / (2 * BALANCE_DECIMALS));
        offers[0].obligationUnits = offerUnits0;
        offers[1].obligationUnits = offerUnits1;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        midnight.touchObligation(obligation);
        uint256 _tradingFee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 sellerPrice = price - _tradingFee;
        uint256 units = targetSellerAssets.mulDivUp(WAD, sellerPrice).mulDivUp(BALANCE_DECIMALS, 1);
        uint256 fromOffer0 = UtilsLib.min(units, offerUnits0);

        // Simulate the bundler's 2-leg splitting to determine exact debt and check round-trip.
        uint256 firstLegSellerAssets = fromOffer0.mulDivDown(sellerPrice, WAD).mulDivDown(1, BALANCE_DECIMALS);
        uint256 secondLegUnits;
        uint256 totalDebt;
        if (firstLegSellerAssets < targetSellerAssets && fromOffer0 < units) {
            uint256 remaining = targetSellerAssets - firstLegSellerAssets;
            secondLegUnits = remaining.mulDivUp(WAD, sellerPrice).mulDivUp(BALANCE_DECIMALS, 1);
            // Filter cases where the 2-leg round-trip doesn't produce exactly targetSellerAssets.
            uint256 secondLegFilled = secondLegUnits.mulDivDown(sellerPrice, WAD).mulDivDown(1, BALANCE_DECIMALS);
            vm.assume(firstLegSellerAssets + secondLegFilled == targetSellerAssets);
            totalDebt = fromOffer0 + secondLegUnits;
        } else {
            secondLegUnits = 0;
            totalDebt = fromOffer0;
        }

        // Provide exact collateral coverage for actual total debt.
        collateralize(obligation, borrower, totalDebt + 1);

        TakeBundler.Take[] memory takes = new TakeBundler.Take[](2);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            obligationUnits: offerUnits0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            obligationUnits: offerUnits1,
            sig: sig([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        if (fromOffer0 >= units || offerUnits1 >= secondLegUnits) {
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
        // Returns token-scale buyer assets (divided by BALANCE_DECIMALS).
        return fromOffer0.mulDivDown(TickLib.tickToPrice(tick0), WAD).mulDivDown(1, BALANCE_DECIMALS)
            + fromOffer1.mulDivDown(TickLib.tickToPrice(tick1), WAD).mulDivDown(1, BALANCE_DECIMALS);
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
        offers[0].obligationUnits = offerUnits0;
        offers[0].tick = tick0;
        offers[1].obligationUnits = offerUnits1;
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
            obligationUnits: offerUnits0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            obligationUnits: offerUnits1,
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
        offers[0].obligationUnits = offerUnits0;
        offers[0].tick = tick0;
        offers[1].obligationUnits = offerUnits1;
        offers[1].tick = tick1;

        uint256 fromOffer0 = UtilsLib.min(targetUnits, offerUnits0);
        vm.assume(offerUnits1 >= targetUnits - fromOffer0);

        uint256 expected = _expectedBuyerAssets(targetUnits, offerUnits0, tick0, tick1);
        minBuyerAssets = bound(minBuyerAssets, expected + 1, type(uint256).max);

        collateralize(obligation, borrower, targetUnits);

        TakeBundler.Take[] memory takes = new TakeBundler.Take[](2);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            obligationUnits: offerUnits0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            obligationUnits: offerUnits1,
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
