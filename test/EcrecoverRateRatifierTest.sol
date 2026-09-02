// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";
import {EcrecoverRateRatifier} from "../src/ratifiers/EcrecoverRateRatifier.sol";
import {IEcrecoverRateRatifier} from "../src/ratifiers/interfaces/IEcrecoverRateRatifier.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {BaseTest} from "./BaseTest.sol";

contract EcrecoverRateRatifierTest is BaseTest {
    EcrecoverRateRatifier internal ecrecoverRateRatifier;

    function setUp() public override {
        super.setUp();
        ecrecoverRateRatifier = new EcrecoverRateRatifier(address(midnight));
    }

    function buildRatifierData(bytes32 _root, uint256 startRate, uint256 expiryRate, address signer)
        internal
        view
        returns (bytes memory)
    {
        Signature memory sig = rateSignature(_root, privateKey[signer], address(ecrecoverRateRatifier), 0);
        return abi.encode(sig, _root, 0, new bytes32[](0), startRate, expiryRate);
    }

    function buildRatifierData(Offer memory offer, uint256 startRate, uint256 expiryRate, address signer)
        internal
        view
        returns (bytes memory)
    {
        return buildRatifierData(HashLib.hashRateOffer(offer, startRate, expiryRate), startRate, expiryRate, signer);
    }

    function makeOffer(address maker, bool buy) internal view returns (Offer memory offer) {
        offer.maker = maker;
        offer.buy = buy;
        offer.ratifier = address(ecrecoverRateRatifier);
        offer.expiry = vm.getBlockTimestamp() + 365 days;
        offer.market.maturity = vm.getBlockTimestamp() + 2 * 365 days;
    }

    /// @dev Per-second WAD rate giving ~10% over 1 year via simple interest: rate = 0.1e18 / 365 days.
    function rate10pct() internal pure returns (uint256) {
        return uint256(0.1e18) / 365 days;
    }

    function testDomainSeparator() public view {
        bytes32 _domainSeparator =
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(ecrecoverRateRatifier)));
        bytes32 expectedDomainSeparator = vm.eip712HashStruct(
            "EIP712Domain(uint256 chainId,address verifyingContract)",
            abi.encode(block.chainid, address(ecrecoverRateRatifier))
        );
        assertEq(_domainSeparator, expectedDomainSeparator);
    }

    function testIsRatifiedValidSignature(uint256 privateKey) public {
        privateKey = boundPrivateKey(privateKey);
        address maker = vm.addr(privateKey);

        Offer memory offer;
        offer.maker = maker;
        offer.buy = true;
        offer.tick = 0;
        offer.ratifier = address(ecrecoverRateRatifier);
        bytes32 root = HashLib.hashRateOffer(offer, 0, 0);

        Signature memory _sig = rateSignature(root, privateKey, address(ecrecoverRateRatifier), 0);

        vm.prank(address(midnight));
        bytes32 result = ecrecoverRateRatifier.isRatified(
            offer, abi.encode(_sig, root, 0, new bytes32[](0), uint256(0), uint256(0)), address(0)
        );
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testIsRatifiedBuyerSigns() public {
        Offer memory offer = makeOffer(lender, true);
        uint256 rate = rate10pct();
        offer.tick = 0;
        bytes memory data = buildRatifierData(offer, rate, rate, lender);

        vm.prank(address(midnight));
        assertEq(ecrecoverRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testIsRatifiedSellerSigns() public {
        Offer memory offer = makeOffer(borrower, false);
        uint256 rate = rate10pct();
        offer.tick = MAX_TICK;
        bytes memory data = buildRatifierData(offer, rate, rate, borrower);

        vm.prank(address(midnight));
        assertEq(ecrecoverRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testIsRatifiedAuthorizedSigns() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);
        bytes memory data = buildRatifierData(offer, rate, rate, borrower);

        vm.prank(address(midnight));
        assertEq(ecrecoverRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testIsRatifiedUnauthorizedSigner() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();
        bytes memory data = buildRatifierData(offer, rate, rate, borrower);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.Unauthorized.selector);
        ecrecoverRateRatifier.isRatified(offer, data, address(0));
    }

    function testIsRatifiedInvalidSignature() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();
        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate);
        bytes memory data = abi.encode(
            Signature({v: 27, r: bytes32(uint256(1)), s: bytes32(uint256(2))}),
            _root,
            uint256(0),
            new bytes32[](0),
            rate,
            rate
        );

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.Unauthorized.selector);
        ecrecoverRateRatifier.isRatified(offer, data, address(0));
    }

    function testIsRatifiedWrongRoot() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();
        bytes32 wrongRoot = keccak256("wrong");
        bytes memory data = buildRatifierData(wrongRoot, rate, rate, lender);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.InvalidProof.selector);
        ecrecoverRateRatifier.isRatified(offer, data, address(0));
    }

    function testIsRatifiedWorksForUnorderedTree() public {
        uint256 rate = rate10pct();
        Offer memory leftOffer = makeOffer(lender, true);
        leftOffer.tick = 0;
        Offer memory rightOffer = makeOffer(lender, true);
        rightOffer.tick = 0;
        rightOffer.expiry += 1;

        bytes32 leftHash = HashLib.hashRateOffer(leftOffer, rate, rate);
        bytes32 rightHash = HashLib.hashRateOffer(rightOffer, rate, rate);
        if (leftHash < rightHash) {
            (leftOffer, rightOffer) = (rightOffer, leftOffer);
            (leftHash, rightHash) = (rightHash, leftHash);
        }

        bytes32 root = HashLib.hashNode(leftHash, rightHash);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leftHash;
        Signature memory sig = rateSignature(root, privateKey[lender], address(ecrecoverRateRatifier), 1);
        bytes memory ratifierData = abi.encode(sig, root, 1, proof, rate, rate);

        vm.prank(address(midnight));
        bytes32 result = ecrecoverRateRatifier.isRatified(rightOffer, ratifierData, address(0));
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testCancelRootMaker() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();
        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate);
        bytes memory ratifierData = buildRatifierData(_root, rate, rate, lender);

        vm.expectEmit();
        emit IEcrecoverRateRatifier.CancelRoot(lender, lender, _root);
        vm.prank(lender);
        ecrecoverRateRatifier.cancelRoot(lender, _root);

        assertTrue(ecrecoverRateRatifier.isRootCanceled(lender, _root));

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.RootCanceled.selector);
        ecrecoverRateRatifier.isRatified(offer, ratifierData, address(0));
    }

    function testCancelRootAuthorizedOnBehalf() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();
        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate);
        bytes memory ratifierData = buildRatifierData(_root, rate, rate, lender);

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        vm.prank(borrower);
        ecrecoverRateRatifier.cancelRoot(lender, _root);

        assertTrue(ecrecoverRateRatifier.isRootCanceled(lender, _root));

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.RootCanceled.selector);
        ecrecoverRateRatifier.isRatified(offer, ratifierData, address(0));
    }

    function testCancelRootUnauthorizedOnBehalf() public {
        bytes32 _root = keccak256("root");

        vm.prank(borrower);
        vm.expectRevert(IEcrecoverRateRatifier.Unauthorized.selector);
        ecrecoverRateRatifier.cancelRoot(lender, _root);
    }

    function testIsRatifiedRevokeAuthorizationInvalidates() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);
        bytes memory ratifierData = buildRatifierData(offer, rate, rate, borrower);

        // Works while authorized.
        vm.prank(address(midnight));
        ecrecoverRateRatifier.isRatified(offer, ratifierData, address(0));

        // Revoke.
        vm.prank(lender);
        midnight.setIsAuthorized(borrower, false, lender);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.Unauthorized.selector);
        ecrecoverRateRatifier.isRatified(offer, ratifierData, address(0));
    }

    function testWorsePriceBuyer() public {
        Offer memory offer = makeOffer(lender, true);
        uint256 rate = rate10pct();
        offer.tick = MAX_TICK;
        bytes memory data = buildRatifierData(offer, rate, rate, lender);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.WorsePrice.selector);
        ecrecoverRateRatifier.isRatified(offer, data, address(0));
    }

    function testWorsePriceSeller() public {
        Offer memory offer = makeOffer(borrower, false);
        uint256 rate = rate10pct();
        offer.tick = 0;
        bytes memory data = buildRatifierData(offer, rate, rate, borrower);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.WorsePrice.selector);
        ecrecoverRateRatifier.isRatified(offer, data, address(0));
    }

    function testRateZeroBuyerAcceptsAnyTick() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = MAX_TICK;
        bytes memory data = buildRatifierData(offer, 0, 0, lender);

        vm.prank(address(midnight));
        assertEq(ecrecoverRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testExpiryPastMaturityAcceptsWADPrice() public {
        uint256 rate = rate10pct();
        Offer memory offer = makeOffer(lender, true);
        offer.market.maturity = vm.getBlockTimestamp() + 180 days;
        offer.expiry = offer.market.maturity + 365 days;
        offer.tick = MAX_TICK;
        bytes memory data = buildRatifierData(offer, rate, rate, lender);

        vm.warp(offer.market.maturity - 1 days);
        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.WorsePrice.selector);
        ecrecoverRateRatifier.isRatified(offer, data, address(0));

        vm.warp(offer.market.maturity + 1 days);
        vm.prank(address(midnight));
        assertEq(ecrecoverRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testPriceLimitIncrease() public {
        Offer memory offer = makeOffer(lender, true);
        uint256 rate = rate10pct();
        // Tick price ~0.87e18 between priceLimitDown at t=0 (2yr TTM ~0.833e18) and at expiry (1yr TTM ~0.909e18).
        offer.tick = TickLib.priceToTick(0.87e18, 1);
        bytes memory data = buildRatifierData(offer, rate, rate, lender);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.WorsePrice.selector);
        ecrecoverRateRatifier.isRatified(offer, data, address(0));

        vm.warp(block.timestamp + 365 days);
        vm.prank(address(midnight));
        assertEq(ecrecoverRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testTamperedRateInRatifierData() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();

        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate);
        Signature memory sig = rateSignature(_root, privateKey[lender], address(ecrecoverRateRatifier), 0);
        bytes memory data = abi.encode(sig, _root, 0, new bytes32[](0), rate, rate);

        bytes memory tamperedDataStartRate = abi.encode(sig, _root, 0, new bytes32[](0), rate * 2, rate);
        bytes memory tamperedDataExpiryRate = abi.encode(sig, _root, 0, new bytes32[](0), rate, rate * 2);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.InvalidProof.selector);
        ecrecoverRateRatifier.isRatified(offer, tamperedDataStartRate, address(0));

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.InvalidProof.selector);
        ecrecoverRateRatifier.isRatified(offer, tamperedDataExpiryRate, address(0));

        vm.prank(address(midnight));
        ecrecoverRateRatifier.isRatified(offer, data, address(0));
    }

    function testDutchAuctionFallingRateBuyer() public {
        uint256 startRate = 3 * rate10pct();
        uint256 expiryRate = rate10pct();

        Offer memory offer = makeOffer(lender, true);
        offer.start = block.timestamp;

        // Tick price ~0.75e18 between priceLimitDown at t=0 (3x rate ~0.625e18) and at expiry (1x rate ~0.909e18).
        offer.tick = TickLib.priceToTick(0.75e18, 1);

        bytes memory data = buildRatifierData(offer, startRate, expiryRate, lender);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.WorsePrice.selector);
        ecrecoverRateRatifier.isRatified(offer, data, address(0));

        vm.warp(offer.start + (offer.expiry - offer.start) * 3 / 4);
        vm.prank(address(midnight));
        assertEq(ecrecoverRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testDutchAuctionRisingRateSeller() public {
        uint256 startRate = rate10pct();
        uint256 expiryRate = 3 * rate10pct();

        Offer memory offer = makeOffer(borrower, false);
        offer.start = block.timestamp;

        // Tick price ~0.8e18 between priceLimitUp at expiry (3x rate ~0.769e18) and at t=0 (1x rate ~0.833e18).
        offer.tick = TickLib.priceToTick(0.8e18, 1);

        bytes memory data = buildRatifierData(offer, startRate, expiryRate, borrower);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.WorsePrice.selector);
        ecrecoverRateRatifier.isRatified(offer, data, address(0));

        vm.warp(offer.start + (offer.expiry - offer.start) * 3 / 4);
        vm.prank(address(midnight));
        assertEq(ecrecoverRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testReverseDutchAuctionRisingRateBuyer() public {
        uint256 startRate = rate10pct();
        uint256 expiryRate = 3 * rate10pct();

        Offer memory offer = makeOffer(lender, true);
        offer.start = block.timestamp;
        offer.market.maturity = offer.expiry + 365 days;

        // Tick price ~0.8e18 between priceLimitDown at expiry (3x rate ~0.769e18) and at t=0 (1x rate ~0.833e18).
        offer.tick = TickLib.priceToTick(0.8e18, 1);

        bytes memory data = buildRatifierData(offer, startRate, expiryRate, lender);

        vm.prank(address(midnight));
        assertEq(ecrecoverRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);

        vm.warp(offer.start + (offer.expiry - offer.start) * 3 / 4);
        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.WorsePrice.selector);
        ecrecoverRateRatifier.isRatified(offer, data, address(0));
    }

    function testReverseDutchAuctionFallingRateSeller() public {
        uint256 startRate = 3 * rate10pct();
        uint256 expiryRate = rate10pct();

        Offer memory offer = makeOffer(borrower, false);
        offer.start = block.timestamp;

        // Tick price ~0.75e18 between priceLimitUp at t=0 (3x rate ~0.625e18) and at expiry (1x rate ~0.909e18).
        offer.tick = TickLib.priceToTick(0.75e18, 1);

        bytes memory data = buildRatifierData(offer, startRate, expiryRate, borrower);

        vm.prank(address(midnight));
        assertEq(ecrecoverRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);

        vm.warp(offer.start + (offer.expiry - offer.start) * 3 / 4);
        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.WorsePrice.selector);
        ecrecoverRateRatifier.isRatified(offer, data, address(0));
    }

    function testDutchAuctionInterpolationApproxAtMidpoint() public {
        uint256 startRate = 3 * rate10pct();
        uint256 expiryRate = rate10pct();

        Offer memory offer = makeOffer(lender, true);
        offer.start = block.timestamp;
        // Tick price ~0.75e18 between priceLimitDown at t=0 (3x rate ~0.625e18) and at midpoint (2x rate ~0.769e18).
        offer.tick = TickLib.priceToTick(0.75e18, 1);

        bytes memory data = buildRatifierData(offer, startRate, expiryRate, lender);

        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.WorsePrice.selector);
        ecrecoverRateRatifier.isRatified(offer, data, address(0));

        vm.warp(offer.start + (offer.expiry - offer.start) / 2);
        vm.prank(address(midnight));
        assertEq(ecrecoverRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testDutchAuctionExactRateAtExpiry() public {
        uint256 startRate = 3 * rate10pct();
        uint256 expiryRate = rate10pct();
        uint256 startTime = block.timestamp;
        uint256 duration = 1 hours;

        Offer memory offer = makeOffer(lender, true);
        offer.start = startTime;
        offer.expiry = startTime + duration;
        // Tick price ~0.75e18 between priceLimitDown at midpoint (2x rate ~0.714e18) and at expiry (1x rate ~0.833e18).
        offer.tick = TickLib.priceToTick(0.75e18, 1);

        bytes memory data = buildRatifierData(offer, startRate, expiryRate, lender);

        vm.warp(startTime + duration / 2);
        vm.prank(address(midnight));
        vm.expectRevert(IEcrecoverRateRatifier.WorsePrice.selector);
        ecrecoverRateRatifier.isRatified(offer, data, address(0));

        vm.warp(startTime + duration);
        vm.prank(address(midnight));
        assertEq(ecrecoverRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    /// @dev start == expiry with startRate != expiryRate is nonsensical but we test that it correctly reverts.
    function testDutchAuctionZeroDurationDifferentRatesReverts() public {
        uint256 startRate = 3 * rate10pct();
        uint256 expiryRate = rate10pct();

        Offer memory offer = makeOffer(lender, true);
        offer.start = block.timestamp;
        offer.expiry = block.timestamp;
        offer.tick = TickLib.priceToTick(0.75e18, 1);

        bytes memory data = buildRatifierData(offer, startRate, expiryRate, lender);

        vm.prank(address(midnight));
        vm.expectRevert();
        ecrecoverRateRatifier.isRatified(offer, data, address(0));
    }
}
