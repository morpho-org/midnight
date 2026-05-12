// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {WAD, ORACLE_PRICE_SCALE} from "../src/libraries/ConstantsLib.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {ERC20Permit} from "./erc20s/ERC20Permit.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {MidnightBundles} from "../src/periphery/MidnightBundles.sol";
import {
    IMidnightBundles,
    Take,
    CollateralWithdrawal,
    CollateralSupply,
    TokenPermit,
    PermitKind
} from "../src/periphery/interfaces/IMidnightBundles.sol";
import {Permit2 as VendorPermit2} from "./vendor/Permit2.sol";
import {BaseTest} from "./BaseTest.sol";

contract MidnightBundlesTest is BaseTest {
    using UtilsLib for uint256;

    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    MidnightBundles internal midnightBundles;

    Obligation internal obligation;
    bytes32 internal id;
    Offer[] internal offers;

    function setUp() public override {
        super.setUp();

        midnightBundles = new MidnightBundles();
        deployCodeTo("Permit2", PERMIT2);

        // Set trading fees to max for all breakpoints.
        midnight.setFeeClaimer(makeAddr("feeClaimer"));
        for (uint256 i; i <= 6; i++) {
            midnight.setDefaultTradingFee(address(loanToken), i, maxTradingFee(i));
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

    function _noPermit() internal pure returns (TokenPermit memory) {}

    function _permit2(address token, address owner, uint256 amount, uint256 nonce, uint256 deadline)
        internal
        view
        returns (TokenPermit memory)
    {
        bytes32 tokenPermissionsHash =
            keccak256(abi.encode(keccak256("TokenPermissions(address token,uint256 amount)"), token, amount));
        bytes32 permitHash = keccak256(
            abi.encode(
                keccak256(
                    "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
                ),
                tokenPermissionsHash,
                address(midnightBundles),
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", VendorPermit2(PERMIT2).DOMAIN_SEPARATOR(), permitHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey[owner], digest);
        return TokenPermit({kind: PermitKind.Permit2, data: abi.encode(nonce, deadline, abi.encodePacked(r, s, v))});
    }

    function _erc2612(address token, address owner, uint256 amount, uint256 nonce, uint256 deadline)
        internal
        view
        returns (TokenPermit memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(ERC20Permit(token).PERMIT_TYPEHASH(), owner, address(midnightBundles), amount, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", ERC20Permit(token).DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey[owner], digest);
        return TokenPermit({kind: PermitKind.ERC2612, data: abi.encode(deadline, v, r, s)});
    }

    function testUnauthorized() public {
        offers[0].buy = false;
        offers[0].maker = borrower;

        Take[] memory takes = new Take[](1);
        takes[0] = Take({offer: offers[0], units: 100, ratifierData: merkleRatifierData([offers[0]])});

        vm.prank(address(0xdead));
        vm.expectRevert(IMidnightBundles.Unauthorized.selector);
        midnightBundles.buyWithUnitsTargetAndWithdrawCollateral(
            address(midnight),
            100,
            0,
            lender,
            _noPermit(),
            takes,
            new CollateralWithdrawal[](0),
            address(0),
            0,
            address(0)
        );
    }

    function testSellUnitsTarget(uint256 offerUnits0, uint256 offerUnits1, uint256 units) public {
        units = bound(units, 0, uint256(type(uint128).max) * 3 / 4);
        offers[0].maxUnits = offerUnits0;
        offers[1].maxUnits = offerUnits1;
        uint256 fromOffer0 = UtilsLib.min(units, offerUnits0);

        collateralize(obligation, borrower, units);

        Take[] memory takes = new Take[](2);
        takes[0] = Take({offer: offers[0], units: offerUnits0, ratifierData: merkleRatifierData([offers[0]])});
        takes[1] = Take({offer: offers[1], units: offerUnits1, ratifierData: merkleRatifierData([offers[1]])});

        if (offerUnits1 >= units - fromOffer0) {
            vm.prank(borrower);
            midnightBundles.supplyCollateralAndSellWithUnitsTarget(
                address(midnight), units, 0, borrower, borrower, new CollateralSupply[](0), takes, 0, address(0)
            );

            uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
            uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
            assertEq(consumed0, fromOffer0, "consumed offer 0");
            assertEq(consumed0 + consumed1, midnight.debtOf(id, borrower), "total consumed");
            assertEq(midnight.debtOf(id, borrower), units, "debt");
        } else {
            vm.prank(borrower);
            vm.expectRevert(IMidnightBundles.OutOfOffers.selector);
            midnightBundles.supplyCollateralAndSellWithUnitsTarget(
                address(midnight), units, 0, borrower, borrower, new CollateralSupply[](0), takes, 0, address(0)
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
        takes[0] = Take({offer: offers[0], units: offerUnits0, ratifierData: merkleRatifierData([offers[0]])});
        takes[1] = Take({offer: offers[1], units: offerUnits1, ratifierData: merkleRatifierData([offers[1]])});

        if (offerUnits1 >= units - fromOffer0) {
            vm.prank(lender);
            midnightBundles.buyWithAssetsTargetAndWithdrawCollateral(
                address(midnight),
                targetBuyerAssets,
                0,
                lender,
                _noPermit(),
                takes,
                new CollateralWithdrawal[](0),
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
            midnightBundles.buyWithAssetsTargetAndWithdrawCollateral(
                address(midnight),
                targetBuyerAssets,
                0,
                lender,
                _noPermit(),
                takes,
                new CollateralWithdrawal[](0),
                address(0),
                0,
                address(0)
            );
        }
    }

    function testBuyBuyerAssetsTargetPermit2() public {
        uint256 targetBuyerAssets = 100e18;
        vm.prank(lender);
        loanToken.approve(address(midnightBundles), 0);

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 units = targetBuyerAssets.mulDivUp(WAD, price);
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = units;
        collateralize(obligation, borrower, units);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});

        vm.startPrank(lender);
        loanToken.approve(PERMIT2, targetBuyerAssets);
        vm.stopPrank();

        TokenPermit memory permit = _permit2(address(loanToken), lender, targetBuyerAssets, 0, block.timestamp + 1);
        vm.prank(lender);
        midnightBundles.buyWithAssetsTargetAndWithdrawCollateral(
            address(midnight),
            targetBuyerAssets,
            0,
            lender,
            permit,
            takes,
            new CollateralWithdrawal[](0),
            address(0),
            0,
            address(0)
        );

        assertEq(loanToken.allowance(lender, address(midnightBundles)), 0);
        assertEq(loanToken.allowance(lender, PERMIT2), 0);
        assertEq(loanToken.balanceOf(lender), type(uint256).max - targetBuyerAssets);
        assertEq(midnight.creditOf(id, lender), units);
    }

    function testBuyBuyerAssetsTargetPermit() public {
        uint256 targetBuyerAssets = 100e18;
        vm.prank(lender);
        loanToken.approve(address(midnightBundles), 0);

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 units = targetBuyerAssets.mulDivUp(WAD, price);
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = units;
        collateralize(obligation, borrower, units);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});

        TokenPermit memory permit = _erc2612(address(loanToken), lender, targetBuyerAssets, 0, block.timestamp + 1);
        vm.prank(lender);
        midnightBundles.buyWithAssetsTargetAndWithdrawCollateral(
            address(midnight),
            targetBuyerAssets,
            0,
            lender,
            permit,
            takes,
            new CollateralWithdrawal[](0),
            address(0),
            0,
            address(0)
        );

        assertEq(loanToken.allowance(lender, address(midnightBundles)), 0);
        assertEq(loanToken.balanceOf(lender), type(uint256).max - targetBuyerAssets);
        assertEq(midnight.creditOf(id, lender), units);
    }

    function testBuyUnitsTargetPermit2() public {
        uint256 units = 100e18;
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 maxBuyerAssets = units.mulDivUp(price, WAD);
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = units;
        collateralize(obligation, borrower, units);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});

        vm.startPrank(lender);
        loanToken.approve(address(midnightBundles), 0);
        loanToken.approve(PERMIT2, maxBuyerAssets);
        vm.stopPrank();

        TokenPermit memory permit = _permit2(address(loanToken), lender, maxBuyerAssets, 0, block.timestamp + 1);
        vm.prank(lender);
        midnightBundles.buyWithUnitsTargetAndWithdrawCollateral(
            address(midnight),
            units,
            maxBuyerAssets,
            lender,
            permit,
            takes,
            new CollateralWithdrawal[](0),
            address(0),
            0,
            address(0)
        );

        assertEq(loanToken.allowance(lender, address(midnightBundles)), 0);
        assertEq(loanToken.allowance(lender, PERMIT2), 0);
        assertEq(loanToken.balanceOf(lender), type(uint256).max - maxBuyerAssets);
        assertEq(midnight.creditOf(id, lender), units);
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
        takes[0] = Take({offer: offers[0], units: 1, ratifierData: merkleRatifierData([offers[0]])});
        takes[1] = Take({offer: offers[1], units: 1, ratifierData: merkleRatifierData([offers[1]])});

        vm.prank(lender);
        vm.expectRevert(IMidnightBundles.InconsistentObligation.selector);
        midnightBundles.buyWithUnitsTargetAndWithdrawCollateral(
            address(midnight),
            2,
            type(uint256).max,
            lender,
            _noPermit(),
            takes,
            new CollateralWithdrawal[](0),
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
        takes[0] = Take({offer: offers[0], units: 1, ratifierData: merkleRatifierData([offers[0]])});
        takes[1] = Take({offer: offers[1], units: 1, ratifierData: merkleRatifierData([offers[1]])});

        vm.prank(borrower);
        vm.expectRevert(IMidnightBundles.InconsistentObligation.selector);
        midnightBundles.supplyCollateralAndSellWithUnitsTarget(
            address(midnight), 2, 0, borrower, borrower, new CollateralSupply[](0), takes, 0, address(0)
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
        takes[0] = Take({offer: offers[0], units: 1, ratifierData: merkleRatifierData([offers[0]])});
        takes[1] = Take({offer: offers[1], units: 1, ratifierData: merkleRatifierData([offers[1]])});

        vm.prank(lender);
        vm.expectRevert(IMidnightBundles.InconsistentObligation.selector);
        midnightBundles.buyWithAssetsTargetAndWithdrawCollateral(
            address(midnight),
            1000,
            0,
            lender,
            _noPermit(),
            takes,
            new CollateralWithdrawal[](0),
            address(0),
            0,
            address(0)
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
        takes[0] = Take({offer: offers[0], units: offerUnits0, ratifierData: merkleRatifierData([offers[0]])});
        takes[1] = Take({offer: offers[1], units: offerUnits1, ratifierData: merkleRatifierData([offers[1]])});

        // Mirror the bundler's exact fill logic to derive units needed from offer1.
        // When offer0 fills everything, filledSellerAssets0 >= targetSellerAssets, zeroFloorSub → 0, so
        // neededFromOffer1 = 0.
        uint256 sellerPrice = price - _tradingFee;
        uint256 filledSellerAssets0 = fromOffer0.mulDivDown(sellerPrice, WAD);
        uint256 neededFromOffer1 = targetSellerAssets.zeroFloorSub(filledSellerAssets0).mulDivUp(WAD, sellerPrice);
        if (offerUnits1 >= neededFromOffer1) {
            vm.prank(borrower);
            midnightBundles.supplyCollateralAndSellWithAssetsTarget(
                address(midnight),
                targetSellerAssets,
                type(uint256).max,
                borrower,
                borrower,
                new CollateralSupply[](0),
                takes,
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
            midnightBundles.supplyCollateralAndSellWithAssetsTarget(
                address(midnight),
                targetSellerAssets,
                type(uint256).max,
                borrower,
                borrower,
                new CollateralSupply[](0),
                takes,
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
        takes[0] = Take({offer: offers[0], units: 1, ratifierData: merkleRatifierData([offers[0]])});
        takes[1] = Take({offer: offers[1], units: 1, ratifierData: merkleRatifierData([offers[1]])});

        vm.prank(borrower);
        vm.expectRevert(IMidnightBundles.InconsistentObligation.selector);
        midnightBundles.supplyCollateralAndSellWithAssetsTarget(
            address(midnight),
            1000,
            type(uint256).max,
            borrower,
            borrower,
            new CollateralSupply[](0),
            takes,
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
        takes[0] = Take({offer: offers[0], units: type(uint256).max, ratifierData: merkleRatifierData([offers[0]])});

        vm.prank(lender);
        midnightBundles.buyWithUnitsTargetAndWithdrawCollateral(
            address(midnight),
            units,
            type(uint256).max,
            lender,
            _noPermit(),
            takes,
            new CollateralWithdrawal[](0),
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
        takes[0] = Take({offer: offers[0], units: type(uint256).max, ratifierData: merkleRatifierData([offers[0]])});

        vm.prank(borrower);
        midnightBundles.supplyCollateralAndSellWithUnitsTarget(
            address(midnight), units, 0, borrower, receiver, new CollateralSupply[](0), takes, referralFeePct, referrer
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
        takes[0] = Take({offer: offers[0], units: type(uint256).max, ratifierData: merkleRatifierData([offers[0]])});

        vm.prank(lender);
        midnightBundles.buyWithAssetsTargetAndWithdrawCollateral(
            address(midnight),
            targetBuyerAssets,
            0,
            lender,
            _noPermit(),
            takes,
            new CollateralWithdrawal[](0),
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
        takes[0] = Take({offer: offers[0], units: type(uint256).max, ratifierData: merkleRatifierData([offers[0]])});

        vm.prank(borrower);
        midnightBundles.supplyCollateralAndSellWithAssetsTarget(
            address(midnight),
            targetSellerAssets,
            type(uint256).max,
            borrower,
            receiver,
            new CollateralSupply[](0),
            takes,
            referralFeePct,
            referrer
        );

        assertEq(loanToken.balanceOf(receiver), targetSellerAssets, "receiver net");
        assertEq(loanToken.balanceOf(referrer), expectedFee, "referrer fee");
        assertEq(loanToken.balanceOf(address(midnightBundles)), 0, "bundler residual");
    }

    function testRepayWithReferralFee(uint256 units, uint256 assets, uint256 referralFeePct) public {
        units = bound(units, 1, uint256(type(uint128).max) * 3 / 4);
        referralFeePct = bound(referralFeePct, 0, WAD - 1);
        address referrer = makeAddr("referrer");

        offers[0].maxUnits = units;

        // Zero trading fees so the borrower receives exactly units loan tokens for the sale.
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        Take[] memory sellTakes = new Take[](1);
        sellTakes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});
        collateralize(obligation, borrower, units);
        vm.prank(borrower);
        midnightBundles.supplyCollateralAndSellWithUnitsTarget(
            address(midnight), units, 0, borrower, borrower, new CollateralSupply[](0), sellTakes, 0, address(0)
        );

        // Bound assets so the derived units never exceed outstanding debt.
        uint256 maxAssets = units.mulDivDown(WAD, WAD - referralFeePct);
        assets = bound(assets, 0, maxAssets);
        uint256 expectedFee = assets.mulDivDown(referralFeePct, WAD);
        uint256 expectedUnits = assets - expectedFee;

        // Top up the borrower so they can pay exactly assets.
        deal(address(loanToken), borrower, assets);

        vm.prank(borrower);
        loanToken.approve(address(midnightBundles), assets);

        vm.prank(borrower);
        midnightBundles.repayAndWithdrawCollateral(
            address(midnight),
            obligation,
            assets,
            borrower,
            _noPermit(),
            new CollateralWithdrawal[](0),
            address(0),
            referralFeePct,
            referrer
        );

        assertEq(midnight.debtOf(id, borrower), units - expectedUnits, "debt");
        assertEq(loanToken.balanceOf(referrer), expectedFee, "referrer fee");
        assertEq(loanToken.balanceOf(borrower), 0, "borrower spent assets");
        assertEq(loanToken.balanceOf(address(midnightBundles)), 0, "bundler residual");
    }

    function testRepayWithReferralFeeFullDebtInversion(uint256 debt, uint256 referralFeePct) public {
        debt = bound(debt, 1, uint256(type(uint128).max) * 3 / 4);
        referralFeePct = bound(referralFeePct, 0, WAD - 1);
        address referrer = makeAddr("referrer");

        offers[0].maxUnits = debt;

        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        Take[] memory sellTakes = new Take[](1);
        sellTakes[0] = Take({offer: offers[0], units: debt, ratifierData: merkleRatifierData([offers[0]])});
        collateralize(obligation, borrower, debt);
        vm.prank(borrower);
        midnightBundles.supplyCollateralAndSellWithUnitsTarget(
            address(midnight), debt, 0, borrower, borrower, new CollateralSupply[](0), sellTakes, 0, address(0)
        );

        uint256 assets = debt.mulDivDown(WAD, WAD - referralFeePct);
        uint256 expectedFee = assets.mulDivDown(referralFeePct, WAD);

        deal(address(loanToken), borrower, assets);
        vm.prank(borrower);
        loanToken.approve(address(midnightBundles), assets);

        vm.prank(borrower);
        midnightBundles.repayAndWithdrawCollateral(
            address(midnight),
            obligation,
            assets,
            borrower,
            _noPermit(),
            new CollateralWithdrawal[](0),
            address(0),
            referralFeePct,
            referrer
        );

        assertEq(midnight.debtOf(id, borrower), 0, "debt fully repaid");
        assertEq(loanToken.balanceOf(referrer), expectedFee, "referrer fee");
        assertEq(loanToken.balanceOf(borrower), 0, "borrower spent assets");
        assertEq(loanToken.balanceOf(address(midnightBundles)), 0, "bundler residual");
    }

    function testPctExceeded() public {
        Take[] memory takes = new Take[](1);
        takes[0] = Take({offer: offers[0], units: 1, ratifierData: merkleRatifierData([offers[0]])});

        offers[0].buy = false;
        Take[] memory buyTakes = new Take[](1);
        buyTakes[0] = Take({offer: offers[0], units: 1, ratifierData: merkleRatifierData([offers[0]])});

        vm.startPrank(lender);
        vm.expectRevert(IMidnightBundles.PctExceeded.selector);
        midnightBundles.buyWithUnitsTargetAndWithdrawCollateral(
            address(midnight),
            1,
            0,
            lender,
            _noPermit(),
            buyTakes,
            new CollateralWithdrawal[](0),
            address(0),
            WAD,
            address(0)
        );
        vm.expectRevert(IMidnightBundles.PctExceeded.selector);
        midnightBundles.buyWithAssetsTargetAndWithdrawCollateral(
            address(midnight),
            1,
            0,
            lender,
            _noPermit(),
            buyTakes,
            new CollateralWithdrawal[](0),
            address(0),
            WAD,
            address(0)
        );
        vm.stopPrank();

        vm.startPrank(borrower);
        vm.expectRevert(IMidnightBundles.PctExceeded.selector);
        midnightBundles.supplyCollateralAndSellWithUnitsTarget(
            address(midnight), 1, 0, borrower, borrower, new CollateralSupply[](0), takes, WAD, address(0)
        );
        vm.expectRevert(IMidnightBundles.PctExceeded.selector);
        midnightBundles.supplyCollateralAndSellWithAssetsTarget(
            address(midnight),
            1,
            type(uint256).max,
            borrower,
            borrower,
            new CollateralSupply[](0),
            takes,
            WAD,
            address(0)
        );
        vm.expectRevert(IMidnightBundles.PctExceeded.selector);
        midnightBundles.repayAndWithdrawCollateral(
            address(midnight),
            obligation,
            0,
            borrower,
            _noPermit(),
            new CollateralWithdrawal[](0),
            address(0),
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
        takes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});

        address receiver = makeAddr("collateralReceiver");
        CollateralWithdrawal[] memory withdrawals = new CollateralWithdrawal[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            withdrawals[i] = CollateralWithdrawal({collateralIndex: i, assets: amounts[i] / 4});
        }

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 maxBuyerAssets = units.mulDivUp(price, WAD);

        vm.prank(lender);
        midnightBundles.buyWithUnitsTargetAndWithdrawCollateral(
            address(midnight), units, maxBuyerAssets, lender, _noPermit(), takes, withdrawals, receiver, 0, address(0)
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
        takes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});

        address receiver = makeAddr("collateralReceiver");
        CollateralWithdrawal[] memory withdrawals = new CollateralWithdrawal[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            withdrawals[i] = CollateralWithdrawal({collateralIndex: i, assets: amounts[i] / 4});
        }

        vm.prank(lender);
        midnightBundles.buyWithAssetsTargetAndWithdrawCollateral(
            address(midnight), targetBuyerAssets, 0, lender, _noPermit(), takes, withdrawals, receiver, 0, address(0)
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

        CollateralSupply[] memory supplies = new CollateralSupply[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            uint256 amount = _collateralAmount(i, units / numCollaterals + 1);
            deal(obligation.collateralParams[i].token, borrower, amount);
            vm.prank(borrower);
            ERC20(obligation.collateralParams[i].token).approve(address(midnightBundles), amount);
            supplies[i] = CollateralSupply({collateralIndex: i, assets: amount, permit: _noPermit()});
        }

        Take[] memory takes = new Take[](1);
        takes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});

        vm.prank(borrower);
        midnightBundles.supplyCollateralAndSellWithUnitsTarget(
            address(midnight), units, 0, borrower, borrower, supplies, takes, 0, address(0)
        );

        for (uint256 i; i < numCollaterals; i++) {
            assertEq(midnight.collateral(id, borrower, i), supplies[i].assets);
        }
        assertEq(midnight.debtOf(id, borrower), units);
    }

    function testSellUnitsTargetPermit2() public {
        uint256 units = 100e18;
        offers[0].maxUnits = units;

        uint256 amount = _collateralAmount(0, units);
        deal(obligation.collateralParams[0].token, borrower, amount);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});

        address collateralToken = obligation.collateralParams[0].token;
        vm.startPrank(borrower);
        ERC20(collateralToken).approve(address(midnightBundles), 0);
        ERC20(collateralToken).approve(PERMIT2, amount);
        vm.stopPrank();

        CollateralSupply[] memory supplies = new CollateralSupply[](1);
        supplies[0] = CollateralSupply({
            collateralIndex: 0,
            assets: amount,
            permit: _permit2(collateralToken, borrower, amount, 0, block.timestamp + 1)
        });
        vm.prank(borrower);
        midnightBundles.supplyCollateralAndSellWithUnitsTarget(
            address(midnight), units, 0, borrower, borrower, supplies, takes, 0, address(0)
        );

        assertEq(ERC20(collateralToken).allowance(borrower, address(midnightBundles)), 0);
        assertEq(ERC20(collateralToken).allowance(borrower, PERMIT2), 0);
        assertEq(midnight.collateral(id, borrower, 0), amount);
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
        sellTakes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});
        collateralize(obligation, borrower, units);
        uint256 collateralAmount = midnight.collateral(id, borrower, 0);
        vm.prank(borrower);
        midnightBundles.supplyCollateralAndSellWithUnitsTarget(
            address(midnight), units, 0, borrower, borrower, new CollateralSupply[](0), sellTakes, 0, address(0)
        );

        uint256 maxWithdrawable = collateralAmount - _collateralAmount(0, units - repayUnits);
        withdrawAssets = bound(withdrawAssets, 0, maxWithdrawable);
        address collateralReceiver = makeAddr("collateralReceiver");

        vm.prank(borrower);
        loanToken.approve(address(midnightBundles), repayUnits);

        CollateralWithdrawal[] memory withdrawals = new CollateralWithdrawal[](1);
        withdrawals[0] = CollateralWithdrawal({collateralIndex: 0, assets: withdrawAssets});

        uint256 borrowerLoanBalanceBefore = loanToken.balanceOf(borrower);

        vm.prank(borrower);
        midnightBundles.repayAndWithdrawCollateral(
            address(midnight),
            obligation,
            repayUnits,
            borrower,
            _noPermit(),
            withdrawals,
            collateralReceiver,
            0,
            address(0)
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

        CollateralSupply[] memory supplies = new CollateralSupply[](numCollaterals);
        for (uint256 i; i < numCollaterals; i++) {
            uint256 amount = _collateralAmount(i, units / numCollaterals + 1);
            deal(obligation.collateralParams[i].token, borrower, amount);
            vm.prank(borrower);
            ERC20(obligation.collateralParams[i].token).approve(address(midnightBundles), amount);
            supplies[i] = CollateralSupply({collateralIndex: i, assets: amount, permit: _noPermit()});
        }

        Take[] memory takes = new Take[](1);
        takes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});

        vm.prank(borrower);
        midnightBundles.supplyCollateralAndSellWithAssetsTarget(
            address(midnight), targetSellerAssets, type(uint256).max, borrower, borrower, supplies, takes, 0, address(0)
        );

        for (uint256 i; i < numCollaterals; i++) {
            assertEq(midnight.collateral(id, borrower, i), supplies[i].assets);
        }
        assertEq(loanToken.balanceOf(borrower), targetSellerAssets);
    }

    function testSellSellerAssetsTargetPermit2() public {
        deal(address(loanToken), address(midnightBundles), 0);

        uint256 units = 100e18;
        offers[0].maxUnits = units;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        midnight.touchObligation(obligation);
        uint256 _tradingFee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 targetSellerAssets = units.mulDivDown(price - _tradingFee, WAD);

        uint256 amount = _collateralAmount(0, units);
        deal(obligation.collateralParams[0].token, borrower, amount);

        Take[] memory takes = new Take[](1);
        takes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});

        address collateralToken = obligation.collateralParams[0].token;
        vm.startPrank(borrower);
        ERC20(collateralToken).approve(address(midnightBundles), 0);
        ERC20(collateralToken).approve(PERMIT2, amount);
        vm.stopPrank();

        CollateralSupply[] memory supplies = new CollateralSupply[](1);
        supplies[0] = CollateralSupply({
            collateralIndex: 0,
            assets: amount,
            permit: _permit2(collateralToken, borrower, amount, 0, block.timestamp + 1)
        });
        vm.prank(borrower);
        midnightBundles.supplyCollateralAndSellWithAssetsTarget(
            address(midnight), targetSellerAssets, type(uint256).max, borrower, borrower, supplies, takes, 0, address(0)
        );

        assertEq(ERC20(collateralToken).allowance(borrower, address(midnightBundles)), 0);
        assertEq(ERC20(collateralToken).allowance(borrower, PERMIT2), 0);
        assertEq(midnight.collateral(id, borrower, 0), amount);
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
        takes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});

        vm.prank(lender);
        vm.expectRevert();
        midnightBundles.buyWithUnitsTargetAndWithdrawCollateral(
            address(midnight),
            units,
            price - 1,
            lender,
            _noPermit(),
            takes,
            new CollateralWithdrawal[](0),
            address(0),
            0,
            address(0)
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
        takes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});

        uint256 minSellerAssets = units.mulDivDown(price, WAD) + 1;
        vm.prank(borrower);
        vm.expectRevert(IMidnightBundles.SellerAssetsTooLow.selector);
        midnightBundles.supplyCollateralAndSellWithUnitsTarget(
            address(midnight),
            units,
            minSellerAssets,
            borrower,
            borrower,
            new CollateralSupply[](0),
            takes,
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
        takes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});

        vm.prank(lender);
        vm.expectRevert(IMidnightBundles.UnitsTooLow.selector);
        midnightBundles.buyWithAssetsTargetAndWithdrawCollateral(
            address(midnight),
            units.mulDivUp(price, WAD),
            units + 2,
            lender,
            _noPermit(),
            takes,
            new CollateralWithdrawal[](0),
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
        takes[0] = Take({offer: offers[0], units: units, ratifierData: merkleRatifierData([offers[0]])});

        vm.prank(borrower);
        vm.expectRevert(IMidnightBundles.UnitsTooHigh.selector);
        midnightBundles.supplyCollateralAndSellWithAssetsTarget(
            address(midnight),
            targetSellerAssets,
            price + 1,
            borrower,
            borrower,
            new CollateralSupply[](0),
            takes,
            0,
            address(0)
        );
    }

    // Partially consumed offers: _availableUnits caps the units forwarded to take().

    function testSellUnitsTargetPartiallyConsumed() public {
        offers[0].maxUnits = 100;
        offers[1].maxUnits = 100;

        collateralize(obligation, borrower, 100);

        // Pre-consume 30 of offer 0 (offer.buy=true → maker=lender).
        vm.prank(lender);
        midnight.setConsumed(offers[0].group, 30, lender);

        Take[] memory takes = new Take[](2);
        takes[0] = Take({offer: offers[0], units: 100, ratifierData: merkleRatifierData([offers[0]])});
        takes[1] = Take({offer: offers[1], units: 100, ratifierData: merkleRatifierData([offers[1]])});

        // Offer 0 has 70 available; bundler caps and fills 30 from offer 1.
        vm.prank(borrower);
        midnightBundles.supplyCollateralAndSellWithUnitsTarget(
            address(midnight), 100, 0, borrower, borrower, new CollateralSupply[](0), takes, 0, address(0)
        );

        assertEq(midnight.consumed(offers[0].maker, offers[0].group), 100, "consumed offer 0");
        assertEq(midnight.consumed(offers[1].maker, offers[1].group), 30, "consumed offer 1");
        assertEq(midnight.debtOf(id, borrower), 100, "debt");
    }

    function testSellSellerAssetsTargetPartiallyConsumed() public {
        offers[0].maxUnits = 100;
        offers[1].maxUnits = 100;

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        midnight.touchObligation(obligation);
        uint256 _tradingFee = midnight.tradingFee(id, obligation.maturity - block.timestamp);
        uint256 sellerPrice = price - _tradingFee;
        uint256 targetSellerAssets = uint256(100).mulDivDown(sellerPrice, WAD);

        // Extra collateral headroom for the potential extra unit of debt.
        collateralize(obligation, borrower, 101);

        // Pre-consume 30 of offer 0.
        vm.prank(lender);
        midnight.setConsumed(offers[0].group, 30, lender);

        Take[] memory takes = new Take[](2);
        takes[0] = Take({offer: offers[0], units: 100, ratifierData: merkleRatifierData([offers[0]])});
        takes[1] = Take({offer: offers[1], units: 100, ratifierData: merkleRatifierData([offers[1]])});

        vm.prank(borrower);
        midnightBundles.supplyCollateralAndSellWithAssetsTarget(
            address(midnight),
            targetSellerAssets,
            type(uint256).max,
            borrower,
            borrower,
            new CollateralSupply[](0),
            takes,
            0,
            address(0)
        );

        uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
        uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
        // Offer 0 should hit its cap (consumed 30 + filled up to 70).
        assertEq(consumed0, 100, "consumed offer 0");
        // Total newly filled units equal the borrower's debt.
        assertEq(consumed0 - 30 + consumed1, midnight.debtOf(id, borrower), "total consumed");
        assertEq(loanToken.balanceOf(borrower), targetSellerAssets, "borrower balance");
    }

    function testBuyUnitsTargetPartiallyConsumed() public {
        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = 100;
        offers[1].buy = false;
        offers[1].maker = borrower;
        offers[1].receiverIfMakerIsSeller = borrower;
        offers[1].maxUnits = 100;

        // Reset trading fees so buyerPrice = price <= WAD at MAX_TICK.
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        collateralize(obligation, borrower, 100);

        // Pre-consume 30 of offer 0 (offer.buy=false → maker=borrower).
        vm.prank(borrower);
        midnight.setConsumed(offers[0].group, 30, borrower);

        Take[] memory takes = new Take[](2);
        takes[0] = Take({offer: offers[0], units: 100, ratifierData: merkleRatifierData([offers[0]])});
        takes[1] = Take({offer: offers[1], units: 100, ratifierData: merkleRatifierData([offers[1]])});

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 maxBuyerAssets = uint256(100).mulDivUp(price, WAD);

        vm.prank(lender);
        midnightBundles.buyWithUnitsTargetAndWithdrawCollateral(
            address(midnight),
            100,
            maxBuyerAssets,
            lender,
            _noPermit(),
            takes,
            new CollateralWithdrawal[](0),
            address(0),
            0,
            address(0)
        );

        assertEq(midnight.consumed(offers[0].maker, offers[0].group), 100, "consumed offer 0");
        assertEq(midnight.consumed(offers[1].maker, offers[1].group), 30, "consumed offer 1");
        assertEq(midnight.debtOf(id, borrower), 100, "debt");
    }

    function testBuyBuyerAssetsTargetPartiallyConsumed() public {
        offers[0].buy = false;
        offers[0].maker = borrower;
        offers[0].receiverIfMakerIsSeller = borrower;
        offers[0].maxUnits = 100;
        offers[1].buy = false;
        offers[1].maker = borrower;
        offers[1].receiverIfMakerIsSeller = borrower;
        offers[1].maxUnits = 100;

        // Reset trading fees so buyerPrice = price <= WAD at MAX_TICK.
        for (uint256 i; i <= 6; i++) {
            midnight.setObligationTradingFee(id, i, 0);
        }

        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 targetBuyerAssets = uint256(100).mulDivDown(price, WAD);

        collateralize(obligation, borrower, 100);

        // Pre-consume 30 of offer 0.
        vm.prank(borrower);
        midnight.setConsumed(offers[0].group, 30, borrower);

        Take[] memory takes = new Take[](2);
        takes[0] = Take({offer: offers[0], units: 100, ratifierData: merkleRatifierData([offers[0]])});
        takes[1] = Take({offer: offers[1], units: 100, ratifierData: merkleRatifierData([offers[1]])});

        vm.prank(lender);
        midnightBundles.buyWithAssetsTargetAndWithdrawCollateral(
            address(midnight),
            targetBuyerAssets,
            0,
            lender,
            _noPermit(),
            takes,
            new CollateralWithdrawal[](0),
            address(0),
            0,
            address(0)
        );

        uint256 consumed0 = midnight.consumed(offers[0].maker, offers[0].group);
        uint256 consumed1 = midnight.consumed(offers[1].maker, offers[1].group);
        assertEq(consumed0, 100, "consumed offer 0");
        assertEq(consumed0 - 30 + consumed1, midnight.debtOf(id, borrower), "total consumed");
    }
}
