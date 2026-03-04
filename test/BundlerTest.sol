// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Collateral} from "../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, TICK_RANGE} from "../src/libraries/TickLib.sol";
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

        id = toId(obligation);

        offers.push();
        offers[0].buy = true;
        offers[0].maker = lender;
        offers[0].obligation = obligation;
        offers[0].expiry = block.timestamp + 200;
        offers[0].tick = TICK_RANGE;

        offers.push();
        offers[1].buy = true;
        offers[1].maker = lender;
        offers[1].obligation = obligation;
        offers[1].expiry = block.timestamp + 200;
        offers[1].tick = TICK_RANGE;
        offers[1].group = bytes32(uint256(1));

        deal(address(loanToken), lender, type(uint256).max);
    }

    function _authorizeBundler() internal {
        vm.prank(borrower);
        midnight.setIsAuthorized(address(takeBundler), true);

        vm.prank(borrower);
        midnight.setIsAuthorized(address(this), true);
    }

    function testUnauthorizedShares() public {
        TakeBundler.Take[] memory takes = new TakeBundler.Take[](1);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            obligationShares: 100,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });

        vm.prank(address(0xdead));
        vm.expectRevert("unauthorized");
        takeBundler.bundleTakeShares(midnight, 100, borrower, address(0), takes);
    }

    function testBundleTakeShares(uint256 offerShares0, uint256 offerShares1, uint256 targetShares) public {
        targetShares = bound(targetShares, 0, uint256(type(uint128).max) * 3 / 4);
        offers[0].obligationShares = offerShares0;
        offers[1].obligationShares = offerShares1;
        uint256 fromOffer0 = UtilsLib.min(targetShares, offerShares0);

        collateralize(obligation, borrower, targetShares);

        TakeBundler.Take[] memory takes = new TakeBundler.Take[](2);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            obligationShares: offerShares0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            obligationShares: offerShares1,
            sig: sig([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        if (offerShares1 >= targetShares - fromOffer0) {
            vm.prank(borrower);
            takeBundler.bundleTakeShares(midnight, targetShares, borrower, address(0), takes);

            assertEq(midnight.debtOf(id, borrower), targetShares, "debt");

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
        } else {
            vm.prank(borrower);
            vm.expectRevert("insufficient liquidity");
            takeBundler.bundleTakeShares(midnight, targetShares, borrower, address(0), takes);
        }
    }

    function testBundleTakeUnits(uint256 offerShares0, uint256 offerShares1, uint256 units) public {
        units = bound(units, 0, uint256(type(uint128).max) * 3 / 4);
        offers[0].obligationShares = offerShares0;
        offers[1].obligationShares = offerShares1;
        uint256 fromOffer0 = UtilsLib.min(units, offerShares0);

        collateralize(obligation, borrower, units);

        TakeBundler.Take[] memory takes = new TakeBundler.Take[](2);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            obligationShares: offerShares0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            obligationShares: offerShares1,
            sig: sig([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        if (offerShares1 >= units - fromOffer0) {
            vm.prank(borrower);
            takeBundler.bundleTakeUnits(midnight, units, borrower, address(0), takes);

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(midnight.debtOf(id, borrower), units, "debt");
        } else {
            vm.prank(borrower);
            vm.expectRevert("insufficient liquidity");
            takeBundler.bundleTakeUnits(midnight, units, borrower, address(0), takes);
        }
    }

    function testBundleTakeBuyerAssets(uint256 offerShares0, uint256 offerShares1, uint256 targetBuyerAssets) public {
        targetBuyerAssets = bound(targetBuyerAssets, 1, uint256(type(uint128).max) / 2);
        offers[0].obligationShares = offerShares0;
        offers[1].obligationShares = offerShares1;

        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        uint256 units = targetBuyerAssets.mulDivUp(WAD, price);
        uint256 fromOffer0 = UtilsLib.min(units, offerShares0);

        collateralize(obligation, borrower, units);

        TakeBundler.Take[] memory takes = new TakeBundler.Take[](2);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            obligationShares: offerShares0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            obligationShares: offerShares1,
            sig: sig([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        if (offerShares1 >= units - fromOffer0) {
            vm.prank(borrower);
            takeBundler.bundleTakeBuyerAssets(midnight, targetBuyerAssets, borrower, address(0), takes);

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(loanToken.balanceOf(lender), type(uint256).max - targetBuyerAssets, "lender balance");
        } else {
            vm.prank(borrower);
            vm.expectRevert("insufficient liquidity");
            takeBundler.bundleTakeBuyerAssets(midnight, targetBuyerAssets, borrower, address(0), takes);
        }
    }

    function testBundleTakeSellerAssets(uint256 offerShares0, uint256 offerShares1, uint256 targetSellerAssets) public {
        targetSellerAssets = bound(targetSellerAssets, 1, uint256(type(uint128).max) / 2);
        offers[0].obligationShares = offerShares0;
        offers[1].obligationShares = offerShares1;

        uint256 price = TickLib.tickToPrice(TICK_RANGE);
        midnight.touchObligation(obligation);
        uint256 _tradingFee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 units = targetSellerAssets.mulDivUp(WAD, price - _tradingFee);
        uint256 fromOffer0 = UtilsLib.min(units, offerShares0);

        // Extra collateral headroom for the potential extra unit of debt.
        collateralize(obligation, borrower, units + 1);

        TakeBundler.Take[] memory takes = new TakeBundler.Take[](2);
        takes[0] = TakeBundler.Take({
            offer: offers[0],
            obligationShares: offerShares0,
            sig: sig([offers[0]]),
            root: root([offers[0]]),
            proof: proof([offers[0]])
        });
        takes[1] = TakeBundler.Take({
            offer: offers[1],
            obligationShares: offerShares1,
            sig: sig([offers[1]]),
            root: root([offers[1]]),
            proof: proof([offers[1]])
        });

        _authorizeBundler();

        // Splitting across offers can cause up to 1 extra share of debt due to rounding.
        if (fromOffer0 >= units || offerShares1 >= units + 1 - fromOffer0) {
            vm.prank(borrower);
            takeBundler.bundleTakeSellerAssets(midnight, targetSellerAssets, borrower, borrower, takes);

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(loanToken.balanceOf(borrower), targetSellerAssets, "borrower balance");
        } else {
            vm.prank(borrower);
            vm.expectRevert("insufficient liquidity");
            takeBundler.bundleTakeSellerAssets(midnight, targetSellerAssets, borrower, borrower, takes);
        }
    }
}
