// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {CollateralParams, Market, Offer} from "../src/interfaces/IMidnight.sol";
import {RateRatifierV1} from "../src/ratifiers/RateRatifierV1.sol";
import {IRateRatifierV1} from "../src/ratifiers/interfaces/IRateRatifierV1.sol";
import {CALLBACK_SUCCESS, SET_IS_ROOT_RATIFIED_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

contract RateRatifierV1Test is BaseTest {
    RateRatifierV1 internal rateRatifier;

    function setUp() public override {
        super.setUp();
        rateRatifier = new RateRatifierV1(address(midnight));

        vm.prank(lender);
        midnight.setIsAuthorized(address(this), true, lender);
        vm.prank(borrower);
        midnight.setIsAuthorized(address(this), true, borrower);
    }

    function makeOffer(address maker, bool buy) internal view returns (Offer memory offer) {
        Market memory market;
        market.loanToken = address(loanToken);
        market.chainId = block.chainid;
        market.midnight = address(midnight);
        market.maturity = vm.getBlockTimestamp() + 2 * 365 days;
        market.collateralParams = new CollateralParams[](1);
        market.collateralParams[0] = CollateralParams({
            token: address(collateralToken1),
            lltv: LLTV,
            liquidationCursor: LIQUIDATION_CURSOR,
            oracle: address(oracle1)
        });

        offer.market = market;
        offer.buy = buy;
        offer.maker = maker;
        offer.ratifier = address(rateRatifier);
        offer.maxUnits = type(uint128).max;
        offer.expiry = vm.getBlockTimestamp() + 365 days;
    }

    /// @dev Per-second WAD rate giving ~10% over 1 year via simple interest: rate = 0.1e18 / 365 days.
    function rate10pct() internal pure returns (uint256) {
        return uint256(0.1e18) / 365 days;
    }

    function buildRatifierData(bytes32 root, uint256 startRate, uint256 expiryRate)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(root, uint256(0), new bytes32[](0), startRate, expiryRate, address(0));
    }

    function buildRatifierData(Offer memory offer, uint256 startRate, uint256 expiryRate)
        internal
        pure
        returns (bytes memory)
    {
        return buildRatifierData(HashLib.hashRateOffer(offer, startRate, expiryRate, address(0)), startRate, expiryRate);
    }

    /// @dev The status and the nonce share a slot, so they come back as a tuple from the generated getter.
    function rootNonce(address maker, bytes32 root) internal view returns (uint128) {
        (, uint128 nonce) = rateRatifier.ratification(maker, root);
        return nonce;
    }

    function testSetIsRootRatifiedMaker() public {
        bytes32 _root = keccak256("root");

        vm.expectEmit();
        emit IRateRatifierV1.SetIsRootRatified(lender, lender, _root, true);

        vm.prank(lender);
        assertEq(rateRatifier.setIsRootRatified(lender, _root, true), SET_IS_ROOT_RATIFIED_SUCCESS);

        assertTrue(rateRatifier.isRootRatified(lender, _root));
    }

    function testIsRatifiedAuthorizedSetterCanRatifyOnBehalf() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = MAX_TICK;
        bytes32 _root = HashLib.hashRateOffer(offer, 0, 0, address(0));

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        vm.prank(borrower);
        rateRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        bytes32 result =
            rateRatifier.isRatified(offer, abi.encode(_root, 0, new bytes32[](0), 0, 0, address(0)), address(0));
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testTakeAuthorizedSetterCanRatifyOnBehalf() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = MAX_TICK;
        bytes32 _root = HashLib.hashRateOffer(offer, 0, 0, address(0));

        vm.prank(lender);
        midnight.setIsAuthorized(address(rateRatifier), true, lender);
        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        vm.prank(borrower);
        rateRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(borrower);
        midnight.take(
            offer, abi.encode(_root, 0, new bytes32[](0), 0, 0, address(0)), 0, borrower, borrower, address(0), hex""
        );
    }

    function testIsRatifiedUsesLeafIndex() public {
        Offer memory leftOffer = makeOffer(lender, true);
        leftOffer.tick = MAX_TICK;
        Offer memory rightOffer = makeOffer(lender, true);
        rightOffer.tick = MAX_TICK;
        rightOffer.expiry += 1;

        bytes32 _root = HashLib.hashNode(
            HashLib.hashRateOffer(leftOffer, 0, 0, address(0)), HashLib.hashRateOffer(rightOffer, 0, 0, address(0))
        );
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = HashLib.hashRateOffer(leftOffer, 0, 0, address(0));

        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.InvalidProof.selector);
        rateRatifier.isRatified(rightOffer, abi.encode(_root, 0, proof, 0, 0, address(0)), address(0));

        vm.prank(address(midnight));
        bytes32 result = rateRatifier.isRatified(rightOffer, abi.encode(_root, 1, proof, 0, 0, address(0)), address(0));
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testSetIsRootRatifiedUnauthorizedOnBehalf() public {
        bytes32 _root = keccak256("root");

        vm.prank(borrower);
        vm.expectRevert(IRateRatifierV1.Unauthorized.selector);
        rateRatifier.setIsRootRatified(lender, _root, true);
    }

    function testSetIsRootRatifiedCanUnratify() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();
        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, address(0));
        bytes memory data = buildRatifierData(_root, rate, rate);

        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);

        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, false);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.NotRatified.selector);
        rateRatifier.isRatified(offer, data, address(0));
    }

    function testIsRatifiedBuyer() public {
        Offer memory offer = makeOffer(lender, true);
        uint256 rate = rate10pct();
        offer.tick = 0;

        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, address(0));
        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, buildRatifierData(_root, rate, rate), address(0)), CALLBACK_SUCCESS);
    }

    function testIsRatifiedSeller() public {
        Offer memory offer = makeOffer(borrower, false);
        uint256 rate = rate10pct();
        offer.tick = MAX_TICK;

        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, address(0));
        vm.prank(borrower);
        rateRatifier.setIsRootRatified(borrower, _root, true);

        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, buildRatifierData(_root, rate, rate), address(0)), CALLBACK_SUCCESS);
    }

    function testNotRatified() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.NotRatified.selector);
        rateRatifier.isRatified(offer, buildRatifierData(offer, rate, rate), address(0));
    }

    function testIsRatifiedWrongRoot() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();
        bytes32 wrongRoot = keccak256("wrong");

        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, wrongRoot, true);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.InvalidProof.selector);
        rateRatifier.isRatified(offer, buildRatifierData(wrongRoot, rate, rate), address(0));
    }

    function testTamperedRateInRatifierData() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();

        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, address(0));
        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);

        bytes memory data = abi.encode(_root, uint256(0), new bytes32[](0), rate, rate, address(0));
        bytes memory tamperedDataStartRate = abi.encode(_root, uint256(0), new bytes32[](0), rate * 2, rate, address(0));
        bytes memory tamperedDataExpiryRate =
            abi.encode(_root, uint256(0), new bytes32[](0), rate, rate * 2, address(0));

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.InvalidProof.selector);
        rateRatifier.isRatified(offer, tamperedDataStartRate, address(0));

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.InvalidProof.selector);
        rateRatifier.isRatified(offer, tamperedDataExpiryRate, address(0));

        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testOfferExpired() public {
        Offer memory offer = makeOffer(lender, true);
        bytes memory data = buildRatifierData(offer, rate10pct(), rate10pct());

        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, HashLib.hashRateOffer(offer, rate10pct(), rate10pct(), address(0)), true);

        vm.warp(offer.expiry);
        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);

        vm.warp(offer.expiry + 1);
        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.OfferExpired.selector);
        rateRatifier.isRatified(offer, data, address(0));
    }

    function testWorsePriceBuyer() public {
        Offer memory offer = makeOffer(lender, true);
        uint256 rate = rate10pct();
        offer.tick = MAX_TICK;
        bytes memory data = buildRatifierData(offer, rate, rate);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.WorsePrice.selector);
        rateRatifier.isRatified(offer, data, address(0));
    }

    function testWorsePriceSeller() public {
        Offer memory offer = makeOffer(borrower, false);
        uint256 rate = rate10pct();
        offer.tick = 0;
        bytes memory data = buildRatifierData(offer, rate, rate);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.WorsePrice.selector);
        rateRatifier.isRatified(offer, data, address(0));
    }

    function testRateZeroBuyerAcceptsAnyTick() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = MAX_TICK;

        bytes32 _root = HashLib.hashRateOffer(offer, 0, 0, address(0));
        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, buildRatifierData(_root, 0, 0), address(0)), CALLBACK_SUCCESS);
    }

    function testDutchAuctionFallingRateBuyer() public {
        uint256 startRate = 3 * rate10pct();
        uint256 expiryRate = rate10pct();

        Offer memory offer = makeOffer(lender, true);
        offer.start = block.timestamp;
        // Tick price ~0.75e18 between priceLimitDown at t=0 (3x rate ~0.625e18) and at expiry (1x rate ~0.909e18).
        offer.tick = TickLib.priceToTick(0.75e18, 1);

        bytes32 _root = HashLib.hashRateOffer(offer, startRate, expiryRate, address(0));
        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);

        bytes memory data = buildRatifierData(_root, startRate, expiryRate);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.WorsePrice.selector);
        rateRatifier.isRatified(offer, data, address(0));

        vm.warp(offer.start + (offer.expiry - offer.start) * 3 / 4);
        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testDutchAuctionRisingRateSeller() public {
        uint256 startRate = rate10pct();
        uint256 expiryRate = 3 * rate10pct();

        Offer memory offer = makeOffer(borrower, false);
        offer.start = block.timestamp;
        // Tick price ~0.8e18 between priceLimitUp at expiry (3x rate ~0.769e18) and at t=0 (1x rate ~0.833e18).
        offer.tick = TickLib.priceToTick(0.8e18, 1);

        bytes32 _root = HashLib.hashRateOffer(offer, startRate, expiryRate, address(0));
        vm.prank(borrower);
        rateRatifier.setIsRootRatified(borrower, _root, true);

        bytes memory data = buildRatifierData(_root, startRate, expiryRate);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.WorsePrice.selector);
        rateRatifier.isRatified(offer, data, address(0));

        vm.warp(offer.start + (offer.expiry - offer.start) * 3 / 4);
        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testIsRatifiedWorksForUnorderedTree() public {
        uint256 rate = rate10pct();
        Offer memory leftOffer = makeOffer(lender, true);
        leftOffer.tick = 0;
        Offer memory rightOffer = makeOffer(lender, true);
        rightOffer.tick = 0;
        rightOffer.expiry += 1;

        bytes32 leftHash = HashLib.hashRateOffer(leftOffer, rate, rate, address(0));
        bytes32 rightHash = HashLib.hashRateOffer(rightOffer, rate, rate, address(0));
        if (leftHash < rightHash) {
            (leftOffer, rightOffer) = (rightOffer, leftOffer);
            (leftHash, rightHash) = (rightHash, leftHash);
        }

        bytes32 _root = HashLib.hashNode(leftHash, rightHash);
        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leftHash;
        bytes memory data = abi.encode(_root, uint256(1), proof, rate, rate, address(0));

        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(rightOffer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testExpiryPastMaturityAcceptsWADPrice() public {
        uint256 rate = rate10pct();
        Offer memory offer = makeOffer(lender, true);
        offer.market.maturity = vm.getBlockTimestamp() + 180 days;
        offer.expiry = offer.market.maturity + 365 days;
        offer.tick = MAX_TICK;

        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, address(0));
        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);
        bytes memory data = buildRatifierData(_root, rate, rate);

        vm.warp(offer.market.maturity - 1 days);
        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.WorsePrice.selector);
        rateRatifier.isRatified(offer, data, address(0));

        vm.warp(offer.market.maturity + 1 days);
        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testPriceLimitIncrease() public {
        Offer memory offer = makeOffer(lender, true);
        uint256 rate = rate10pct();
        // Tick price ~0.87e18 between priceLimitDown at t=0 (2yr TTM ~0.833e18) and at expiry (1yr TTM ~0.909e18).
        offer.tick = TickLib.priceToTick(0.87e18, 1);

        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, address(0));
        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);
        bytes memory data = buildRatifierData(_root, rate, rate);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.WorsePrice.selector);
        rateRatifier.isRatified(offer, data, address(0));

        vm.warp(vm.getBlockTimestamp() + 365 days);
        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testReverseDutchAuctionRisingRateBuyer() public {
        uint256 startRate = rate10pct();
        uint256 expiryRate = 3 * rate10pct();

        Offer memory offer = makeOffer(lender, true);
        offer.start = vm.getBlockTimestamp();
        offer.market.maturity = offer.expiry + 365 days;
        // Tick price ~0.8e18 between priceLimitDown at expiry (3x rate ~0.769e18) and at t=0 (1x rate ~0.833e18).
        offer.tick = TickLib.priceToTick(0.8e18, 1);

        bytes32 _root = HashLib.hashRateOffer(offer, startRate, expiryRate, address(0));
        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);
        bytes memory data = buildRatifierData(_root, startRate, expiryRate);

        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);

        vm.warp(offer.start + (offer.expiry - offer.start) * 3 / 4);
        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.WorsePrice.selector);
        rateRatifier.isRatified(offer, data, address(0));
    }

    function testReverseDutchAuctionFallingRateSeller() public {
        uint256 startRate = 3 * rate10pct();
        uint256 expiryRate = rate10pct();

        Offer memory offer = makeOffer(borrower, false);
        offer.start = vm.getBlockTimestamp();
        // Tick price ~0.75e18 between priceLimitUp at t=0 (3x rate ~0.625e18) and at expiry (1x rate ~0.909e18).
        offer.tick = TickLib.priceToTick(0.75e18, 1);

        bytes32 _root = HashLib.hashRateOffer(offer, startRate, expiryRate, address(0));
        vm.prank(borrower);
        rateRatifier.setIsRootRatified(borrower, _root, true);
        bytes memory data = buildRatifierData(_root, startRate, expiryRate);

        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);

        vm.warp(offer.start + (offer.expiry - offer.start) * 3 / 4);
        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.WorsePrice.selector);
        rateRatifier.isRatified(offer, data, address(0));
    }

    function testDutchAuctionInterpolationApproxAtMidpoint() public {
        uint256 startRate = 3 * rate10pct();
        uint256 expiryRate = rate10pct();

        Offer memory offer = makeOffer(lender, true);
        offer.start = vm.getBlockTimestamp();
        // Tick price ~0.75e18 between priceLimitDown at t=0 (3x rate ~0.625e18) and at midpoint (2x rate ~0.769e18).
        offer.tick = TickLib.priceToTick(0.75e18, 1);

        bytes32 _root = HashLib.hashRateOffer(offer, startRate, expiryRate, address(0));
        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);
        bytes memory data = buildRatifierData(_root, startRate, expiryRate);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.WorsePrice.selector);
        rateRatifier.isRatified(offer, data, address(0));

        vm.warp(offer.start + (offer.expiry - offer.start) / 2);
        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testDutchAuctionExactRateAtExpiry() public {
        uint256 startRate = 3 * rate10pct();
        uint256 expiryRate = rate10pct();
        uint256 startTime = vm.getBlockTimestamp();
        uint256 duration = 1 hours;

        Offer memory offer = makeOffer(lender, true);
        offer.start = startTime;
        offer.expiry = startTime + duration;
        // Tick price ~0.75e18 between priceLimitDown at midpoint (2x rate ~0.714e18) and at expiry (1x rate ~0.833e18).
        offer.tick = TickLib.priceToTick(0.75e18, 1);

        bytes32 _root = HashLib.hashRateOffer(offer, startRate, expiryRate, address(0));
        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);
        bytes memory data = buildRatifierData(_root, startRate, expiryRate);

        vm.warp(startTime + duration / 2);
        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.WorsePrice.selector);
        rateRatifier.isRatified(offer, data, address(0));

        vm.warp(offer.expiry);
        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    /// @dev start == expiry with startRate != expiryRate is nonsensical but we test that it correctly reverts.
    function testDutchAuctionZeroDurationDifferentRatesReverts() public {
        uint256 startRate = 3 * rate10pct();
        uint256 expiryRate = rate10pct();

        Offer memory offer = makeOffer(lender, true);
        offer.start = vm.getBlockTimestamp();
        offer.expiry = vm.getBlockTimestamp();
        offer.tick = TickLib.priceToTick(0.75e18, 1);

        bytes32 _root = HashLib.hashRateOffer(offer, startRate, expiryRate, address(0));
        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);
        bytes memory data = buildRatifierData(_root, startRate, expiryRate);

        vm.prank(address(midnight));
        vm.expectRevert();
        rateRatifier.isRatified(offer, data, address(0));
    }

    function testAllowedTaker() public {
        Offer memory offer = makeOffer(lender, true);
        uint256 rate = rate10pct();
        address allowedTaker = borrower;

        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, allowedTaker);
        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, true);

        bytes memory data = abi.encode(_root, uint256(0), new bytes32[](0), rate, rate, allowedTaker);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.UnauthorizedTaker.selector);
        rateRatifier.isRatified(offer, data, otherBorrower);

        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data, allowedTaker), CALLBACK_SUCCESS);

        // Being authorized by `allowedTaker` is not enough: the taker itself must be `allowedTaker`.
        vm.prank(allowedTaker);
        midnight.setIsAuthorized(otherBorrower, true, allowedTaker);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifierV1.UnauthorizedTaker.selector);
        rateRatifier.isRatified(offer, data, otherBorrower);
    }

    function ratifySig(
        address maker,
        bytes32 _root,
        bool newIsRootRatified,
        uint128 nonce,
        uint256 deadline,
        uint256 _privateKey
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 hashStruct = vm.eip712HashStruct(
            "SetIsRootRatified(address maker,bytes32 root,bool newIsRootRatified,uint128 nonce,uint256 deadline)",
            abi.encode(maker, _root, newIsRootRatified, nonce, deadline)
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator(address(rateRatifier)), hashStruct));
        (v, r, s) = vm.sign(_privateKey, digest);
    }

    function testDomainSeparator() public view {
        bytes32 expected = vm.eip712HashStruct(
            "EIP712Domain(uint256 chainId,address verifyingContract)", abi.encode(block.chainid, address(rateRatifier))
        );
        assertEq(rateRatifier.DOMAIN_SEPARATOR(), expected);
    }

    function testSetIsRootRatifiedWithSig() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();
        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, address(0));

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        vm.expectEmit();
        emit IRateRatifierV1.SetIsRootRatifiedWithSig(lender, lender, _root, true, 0, 0);

        vm.prank(borrower);
        assertEq(
            rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s),
            SET_IS_ROOT_RATIFIED_SUCCESS
        );

        assertTrue(rateRatifier.isRootRatified(lender, _root));
        assertEq(rootNonce(lender, _root), 1);

        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, buildRatifierData(_root, rate, rate), address(0)), CALLBACK_SUCCESS);
    }

    function testSetIsRootRatifiedWithSigAuthorizedSigner() public {
        bytes32 _root = keccak256("root");

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[borrower]);

        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);

        assertTrue(rateRatifier.isRootRatified(lender, _root));
    }

    function testSetIsRootRatifiedWithSigUnauthorizedCaller() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);

        vm.prank(otherBorrower);
        vm.expectRevert(IRateRatifierV1.Unauthorized.selector);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
    }

    function testSetIsRootRatifiedWithSigUnauthorizedSigner() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[borrower]);

        vm.expectRevert(IRateRatifierV1.Unauthorized.selector);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
    }

    function testSetIsRootRatifiedWithSigDeadlineExpired() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, deadline, privateKey[lender]);

        vm.warp(deadline + 1);
        vm.expectRevert(IRateRatifierV1.DeadlineExpired.selector);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, v, r, s);
    }

    function testSetIsRootRatifiedWithSigNonceTooHigh() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 1, vm.getBlockTimestamp(), privateKey[lender]);

        vm.expectRevert(IRateRatifierV1.InvalidNonce.selector);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 1, vm.getBlockTimestamp(), v, r, s);
    }

    /// @dev Replaying a consumed signature is a no-op while the status it carries still holds, so that a bundle
    /// carrying it twice does not revert.
    function testSetIsRootRatifiedWithSigReplayNoOp() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);

        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
        assertEq(rootNonce(lender, _root), 1);

        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
        assertTrue(rateRatifier.isRootRatified(lender, _root));
        assertEq(rootNonce(lender, _root), 1, "nonce must not advance twice");
    }

    /// @dev But a consumed signature cannot resurrect a status the maker has since changed.
    function testSetIsRootRatifiedWithSigReplayAfterStatusChange() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);

        vm.prank(lender);
        rateRatifier.setIsRootRatified(lender, _root, false);

        vm.expectRevert(IRateRatifierV1.RatifiedStatusChanged.selector);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
        assertFalse(rateRatifier.isRootRatified(lender, _root));
    }

    function testSetIsRootRatifiedWithSigCanUnratify() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);

        (v, r, s) = ratifySig(lender, _root, false, 1, vm.getBlockTimestamp(), privateKey[lender]);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, false, 1, vm.getBlockTimestamp(), v, r, s);

        assertFalse(rateRatifier.isRootRatified(lender, _root));
        assertEq(rootNonce(lender, _root), 2);
    }

    function testSetIsRootRatifiedWithSigEcrecoverReturnsZero() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, deadline, privateKey[lender]);

        // Valid v values are 27 and 28.
        vm.expectRevert(IRateRatifierV1.InvalidSignature.selector);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, 0, r, s);
    }

    function testSetIsRootRatifiedWithSigStaleNonceChecksSignature() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, deadline, privateKey[lender]);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, v, r, s);

        // Garbage signature.
        vm.expectRevert(IRateRatifierV1.InvalidSignature.selector);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, 0, bytes32(0), bytes32(0));

        // Signature from an account the maker never authorized.
        (v, r, s) = ratifySig(lender, _root, true, 0, deadline, privateKey[borrower]);
        vm.expectRevert(IRateRatifierV1.Unauthorized.selector);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, v, r, s);

        assertTrue(rateRatifier.isRootRatified(lender, _root));
        assertEq(rootNonce(lender, _root), 1);
    }

    function testSetIsRootRatifiedWithSigRejectsTampering() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, deadline, privateKey[lender]);

        // Wrong maker.
        vm.expectRevert(IRateRatifierV1.Unauthorized.selector);
        rateRatifier.setIsRootRatifiedWithSig(borrower, _root, true, 0, deadline, v, r, s);

        // Wrong root.
        vm.expectRevert(IRateRatifierV1.Unauthorized.selector);
        rateRatifier.setIsRootRatifiedWithSig(lender, keccak256("other"), true, 0, deadline, v, r, s);

        // Wrong status.
        vm.expectRevert(IRateRatifierV1.Unauthorized.selector);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, false, 0, deadline, v, r, s);

        // Wrong nonce, checked after the signature so it does not surface as InvalidNonce.
        vm.expectRevert(IRateRatifierV1.Unauthorized.selector);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 1, deadline, v, r, s);

        // Wrong deadline.
        vm.expectRevert(IRateRatifierV1.Unauthorized.selector);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline + 1, v, r, s);

        assertFalse(rateRatifier.isRootRatified(lender, _root));
        assertEq(rootNonce(lender, _root), 0);
    }

    function testSetIsRootRatifiedWithSigRejectsRevokedAuthorization() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, deadline, privateKey[borrower]);

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, false, lender);

        vm.expectRevert(IRateRatifierV1.Unauthorized.selector);
        rateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, v, r, s);
    }
}
