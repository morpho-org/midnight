// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {TakeBundler} from "../src/periphery/TakeBundler.sol";
import {ITakeBundler, Take} from "../src/periphery/interfaces/ITakeBundler.sol";
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
        takeBundler.buyUnitsTarget(address(midnight), 100, borrower, address(0), takes);
    }

    function testBuyUnitsTarget(uint256 offerUnits0, uint256 offerUnits1, uint256 units) public {
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
            takeBundler.buyUnitsTarget(address(midnight), units, borrower, borrower, takes);

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(midnight.debtOf(id, borrower), units, "debt");
        } else {
            vm.prank(borrower);
            vm.expectRevert(ITakeBundler.InsufficientLiquidity.selector);
            takeBundler.buyUnitsTarget(address(midnight), units, borrower, borrower, takes);
        }
    }

    function testBuyAssetsTarget(uint256 offerUnits0, uint256 offerUnits1, uint256 targetBuyerAssets) public {
        targetBuyerAssets = bound(targetBuyerAssets, 1, uint256(type(uint128).max) / 2);
        offers[0].maxUnits = offerUnits0;
        offers[1].maxUnits = offerUnits1;

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

        _authorizeBundler();

        if (offerUnits1 >= units - fromOffer0) {
            vm.prank(borrower);
            takeBundler.buyAssetsTarget(address(midnight), targetBuyerAssets, borrower, borrower, takes);

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(loanToken.balanceOf(lender), type(uint256).max - targetBuyerAssets, "lender balance");
        } else {
            vm.prank(borrower);
            vm.expectRevert(ITakeBundler.InsufficientLiquidity.selector);
            takeBundler.buyAssetsTarget(address(midnight), targetBuyerAssets, borrower, borrower, takes);
        }
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
            takeBundler.sellUnitsTarget(address(midnight), units, borrower, borrower, takes);

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(midnight.debtOf(id, borrower), units, "debt");
        } else {
            vm.prank(borrower);
            vm.expectRevert(ITakeBundler.InsufficientLiquidity.selector);
            takeBundler.sellUnitsTarget(address(midnight), units, borrower, borrower, takes);
        }
    }

    function testSellAssetsTarget(uint256 offerUnits0, uint256 offerUnits1, uint256 targetSellerAssets) public {
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
            takeBundler.sellAssetsTarget(address(midnight), targetSellerAssets, borrower, borrower, takes);

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(loanToken.balanceOf(borrower), targetSellerAssets, "borrower balance");
        } else {
            vm.prank(borrower);
            vm.expectRevert(ITakeBundler.InsufficientLiquidity.selector);
            takeBundler.sellAssetsTarget(address(midnight), targetSellerAssets, borrower, borrower, takes);
        }
    }
}
