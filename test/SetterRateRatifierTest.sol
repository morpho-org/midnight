// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {CollateralParams, Market, Offer} from "../src/interfaces/IMidnight.sol";
import {SetterRateRatifier} from "../src/ratifiers/SetterRateRatifier.sol";
import {ISetterRateRatifier} from "../src/ratifiers/interfaces/ISetterRateRatifier.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

contract SetterRateRatifierTest is BaseTest {
    SetterRateRatifier internal setterRateRatifier;

    function setUp() public override {
        super.setUp();
        setterRateRatifier = new SetterRateRatifier(address(midnight));
    }

    function makeOffer(address maker) internal view returns (Offer memory offer) {
        Market memory market;
        market.loanToken = address(loanToken);
        market.chainId = block.chainid;
        market.midnight = address(midnight);
        market.maturity = vm.getBlockTimestamp() + 100;
        market.collateralParams = new CollateralParams[](1);
        market.collateralParams[0] = CollateralParams({
            token: address(collateralToken1),
            lltv: LLTV,
            liquidationCursor: LIQUIDATION_CURSOR,
            oracle: address(oracle1)
        });

        offer.market = market;
        offer.buy = true;
        offer.maker = maker;
        offer.ratifier = address(setterRateRatifier);
        offer.maxUnits = type(uint128).max;
        offer.expiry = vm.getBlockTimestamp() + 200;
        offer.tick = MAX_TICK;
    }

    function makeOffer(address maker, bool buy) internal view returns (Offer memory offer) {
        offer.maker = maker;
        offer.buy = buy;
        offer.ratifier = address(setterRateRatifier);
        offer.expiry = vm.getBlockTimestamp() + 365 days;
        offer.market.maturity = vm.getBlockTimestamp() + 2 * 365 days;
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
        (, uint128 nonce) = setterRateRatifier.ratification(maker, root);
        return nonce;
    }

    function testSetIsRootRatifiedMaker() public {
        bytes32 _root = keccak256("root");

        vm.expectEmit();
        emit ISetterRateRatifier.SetIsRootRatified(lender, lender, _root, true);

        vm.prank(lender);
        setterRateRatifier.setIsRootRatified(lender, _root, true);

        assertTrue(setterRateRatifier.isRootRatified(lender, _root));
    }

    function testIsRatifiedAuthorizedSetterCanRatifyOnBehalf() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashRateOffer(offer, 0, 0, address(0));

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        vm.prank(borrower);
        setterRateRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        bytes32 result =
            setterRateRatifier.isRatified(offer, abi.encode(_root, 0, new bytes32[](0), 0, 0, address(0)), address(0));
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testTakeAuthorizedSetterCanRatifyOnBehalf() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashRateOffer(offer, 0, 0, address(0));

        vm.prank(lender);
        midnight.setIsAuthorized(address(setterRateRatifier), true, lender);
        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        vm.prank(borrower);
        setterRateRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(borrower);
        midnight.take(
            offer, abi.encode(_root, 0, new bytes32[](0), 0, 0, address(0)), 0, borrower, borrower, address(0), hex""
        );
    }

    function testIsRatifiedUsesLeafIndex() public {
        Offer memory leftOffer = makeOffer(lender);
        Offer memory rightOffer = makeOffer(lender);
        rightOffer.expiry += 1;

        bytes32 _root = HashLib.hashNode(
            HashLib.hashRateOffer(leftOffer, 0, 0, address(0)), HashLib.hashRateOffer(rightOffer, 0, 0, address(0))
        );
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = HashLib.hashRateOffer(leftOffer, 0, 0, address(0));

        vm.prank(lender);
        setterRateRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        vm.expectRevert(ISetterRateRatifier.InvalidProof.selector);
        setterRateRatifier.isRatified(rightOffer, abi.encode(_root, 0, proof, 0, 0, address(0)), address(0));

        vm.prank(address(midnight));
        bytes32 result =
            setterRateRatifier.isRatified(rightOffer, abi.encode(_root, 1, proof, 0, 0, address(0)), address(0));
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testSetIsRootRatifiedUnauthorizedOnBehalf() public {
        bytes32 _root = keccak256("root");

        vm.prank(borrower);
        vm.expectRevert(ISetterRateRatifier.Unauthorized.selector);
        setterRateRatifier.setIsRootRatified(lender, _root, true);
    }

    function testSetIsRootRatifiedCanUnratify() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();
        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, address(0));
        bytes memory data = buildRatifierData(_root, rate, rate);

        vm.prank(lender);
        setterRateRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        assertEq(setterRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);

        vm.prank(lender);
        setterRateRatifier.setIsRootRatified(lender, _root, false);

        vm.prank(address(midnight));
        vm.expectRevert(ISetterRateRatifier.NotRatified.selector);
        setterRateRatifier.isRatified(offer, data, address(0));
    }

    function testIsRatifiedBuyer() public {
        Offer memory offer = makeOffer(lender, true);
        uint256 rate = rate10pct();
        offer.tick = 0;

        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, address(0));
        vm.prank(lender);
        setterRateRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        assertEq(
            setterRateRatifier.isRatified(offer, buildRatifierData(_root, rate, rate), address(0)), CALLBACK_SUCCESS
        );
    }

    function testIsRatifiedSeller() public {
        Offer memory offer = makeOffer(borrower, false);
        uint256 rate = rate10pct();
        offer.tick = MAX_TICK;

        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, address(0));
        vm.prank(borrower);
        setterRateRatifier.setIsRootRatified(borrower, _root, true);

        vm.prank(address(midnight));
        assertEq(
            setterRateRatifier.isRatified(offer, buildRatifierData(_root, rate, rate), address(0)), CALLBACK_SUCCESS
        );
    }

    function testNotRatified() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();

        vm.prank(address(midnight));
        vm.expectRevert(ISetterRateRatifier.NotRatified.selector);
        setterRateRatifier.isRatified(offer, buildRatifierData(offer, rate, rate), address(0));
    }

    function testIsRatifiedWrongRoot() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();
        bytes32 wrongRoot = keccak256("wrong");

        vm.prank(lender);
        setterRateRatifier.setIsRootRatified(lender, wrongRoot, true);

        vm.prank(address(midnight));
        vm.expectRevert(ISetterRateRatifier.InvalidProof.selector);
        setterRateRatifier.isRatified(offer, buildRatifierData(wrongRoot, rate, rate), address(0));
    }

    function testTamperedRateInRatifierData() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();

        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, address(0));
        vm.prank(lender);
        setterRateRatifier.setIsRootRatified(lender, _root, true);

        bytes memory data = abi.encode(_root, uint256(0), new bytes32[](0), rate, rate, address(0));
        bytes memory tamperedDataStartRate = abi.encode(_root, uint256(0), new bytes32[](0), rate * 2, rate, address(0));
        bytes memory tamperedDataExpiryRate =
            abi.encode(_root, uint256(0), new bytes32[](0), rate, rate * 2, address(0));

        vm.prank(address(midnight));
        vm.expectRevert(ISetterRateRatifier.InvalidProof.selector);
        setterRateRatifier.isRatified(offer, tamperedDataStartRate, address(0));

        vm.prank(address(midnight));
        vm.expectRevert(ISetterRateRatifier.InvalidProof.selector);
        setterRateRatifier.isRatified(offer, tamperedDataExpiryRate, address(0));

        vm.prank(address(midnight));
        assertEq(setterRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testOfferExpired() public {
        Offer memory offer = makeOffer(lender, true);
        bytes memory data = buildRatifierData(offer, rate10pct(), rate10pct());

        vm.prank(lender);
        setterRateRatifier.setIsRootRatified(
            lender, HashLib.hashRateOffer(offer, rate10pct(), rate10pct(), address(0)), true
        );

        vm.warp(offer.expiry);
        vm.prank(address(midnight));
        assertEq(setterRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);

        vm.warp(offer.expiry + 1);
        vm.prank(address(midnight));
        vm.expectRevert(ISetterRateRatifier.OfferExpired.selector);
        setterRateRatifier.isRatified(offer, data, address(0));
    }

    function testWorsePriceBuyer() public {
        Offer memory offer = makeOffer(lender, true);
        uint256 rate = rate10pct();
        offer.tick = MAX_TICK;
        bytes memory data = buildRatifierData(offer, rate, rate);

        vm.prank(address(midnight));
        vm.expectRevert(ISetterRateRatifier.WorsePrice.selector);
        setterRateRatifier.isRatified(offer, data, address(0));
    }

    function testWorsePriceSeller() public {
        Offer memory offer = makeOffer(borrower, false);
        uint256 rate = rate10pct();
        offer.tick = 0;
        bytes memory data = buildRatifierData(offer, rate, rate);

        vm.prank(address(midnight));
        vm.expectRevert(ISetterRateRatifier.WorsePrice.selector);
        setterRateRatifier.isRatified(offer, data, address(0));
    }

    function testRateZeroBuyerAcceptsAnyTick() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = MAX_TICK;

        bytes32 _root = HashLib.hashRateOffer(offer, 0, 0, address(0));
        vm.prank(lender);
        setterRateRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        assertEq(setterRateRatifier.isRatified(offer, buildRatifierData(_root, 0, 0), address(0)), CALLBACK_SUCCESS);
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
        setterRateRatifier.setIsRootRatified(lender, _root, true);

        bytes memory data = buildRatifierData(_root, startRate, expiryRate);

        vm.prank(address(midnight));
        vm.expectRevert(ISetterRateRatifier.WorsePrice.selector);
        setterRateRatifier.isRatified(offer, data, address(0));

        vm.warp(offer.start + (offer.expiry - offer.start) * 3 / 4);
        vm.prank(address(midnight));
        assertEq(setterRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
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
        setterRateRatifier.setIsRootRatified(borrower, _root, true);

        bytes memory data = buildRatifierData(_root, startRate, expiryRate);

        vm.prank(address(midnight));
        vm.expectRevert(ISetterRateRatifier.WorsePrice.selector);
        setterRateRatifier.isRatified(offer, data, address(0));

        vm.warp(offer.start + (offer.expiry - offer.start) * 3 / 4);
        vm.prank(address(midnight));
        assertEq(setterRateRatifier.isRatified(offer, data, address(0)), CALLBACK_SUCCESS);
    }

    function testAllowedTaker() public {
        Offer memory offer = makeOffer(lender, true);
        uint256 rate = rate10pct();
        address allowedTaker = borrower;

        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, allowedTaker);
        vm.prank(lender);
        setterRateRatifier.setIsRootRatified(lender, _root, true);

        bytes memory data = abi.encode(_root, uint256(0), new bytes32[](0), rate, rate, allowedTaker);

        vm.prank(address(midnight));
        vm.expectRevert(ISetterRateRatifier.UnauthorizedTaker.selector);
        setterRateRatifier.isRatified(offer, data, otherBorrower);

        vm.prank(address(midnight));
        assertEq(setterRateRatifier.isRatified(offer, data, allowedTaker), CALLBACK_SUCCESS);

        // Being authorized by `allowedTaker` is not enough: the taker itself must be `allowedTaker`.
        vm.prank(allowedTaker);
        midnight.setIsAuthorized(otherBorrower, true, allowedTaker);

        vm.prank(address(midnight));
        vm.expectRevert(ISetterRateRatifier.UnauthorizedTaker.selector);
        setterRateRatifier.isRatified(offer, data, otherBorrower);
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
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator(address(setterRateRatifier)), hashStruct));
        (v, r, s) = vm.sign(_privateKey, digest);
    }

    function testDomainSeparator() public view {
        bytes32 expected = vm.eip712HashStruct(
            "EIP712Domain(uint256 chainId,address verifyingContract)",
            abi.encode(block.chainid, address(setterRateRatifier))
        );
        assertEq(setterRateRatifier.DOMAIN_SEPARATOR(), expected);
    }

    function testSetIsRootRatifiedWithSig() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();
        bytes32 _root = HashLib.hashRateOffer(offer, rate, rate, address(0));

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);

        vm.expectEmit();
        emit ISetterRateRatifier.SetIsRootRatifiedWithSig(lender, lender, _root, true, 0, 0);

        // Anyone can submit the maker's signature.
        vm.prank(borrower);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);

        assertTrue(setterRateRatifier.isRootRatified(lender, _root));
        assertEq(rootNonce(lender, _root), 1);

        vm.prank(address(midnight));
        assertEq(
            setterRateRatifier.isRatified(offer, buildRatifierData(_root, rate, rate), address(0)), CALLBACK_SUCCESS
        );
    }

    function testSetIsRootRatifiedWithSigAuthorizedSigner() public {
        bytes32 _root = keccak256("root");

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[borrower]);

        vm.prank(otherBorrower);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);

        assertTrue(setterRateRatifier.isRootRatified(lender, _root));
    }

    function testSetIsRootRatifiedWithSigUnauthorizedSigner() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[borrower]);

        vm.expectRevert(ISetterRateRatifier.Unauthorized.selector);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
    }

    function testSetIsRootRatifiedWithSigDeadlineExpired() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, deadline, privateKey[lender]);

        vm.warp(deadline + 1);
        vm.expectRevert(ISetterRateRatifier.DeadlineExpired.selector);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, v, r, s);
    }

    function testSetIsRootRatifiedWithSigNonceTooHigh() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 1, vm.getBlockTimestamp(), privateKey[lender]);

        vm.expectRevert(ISetterRateRatifier.InvalidNonce.selector);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 1, vm.getBlockTimestamp(), v, r, s);
    }

    /// @dev Replaying a consumed signature is a no-op while the status it carries still holds, so that a bundle
    /// carrying it twice does not revert.
    function testSetIsRootRatifiedWithSigReplayNoOp() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);

        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
        assertEq(rootNonce(lender, _root), 1);

        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
        assertTrue(setterRateRatifier.isRootRatified(lender, _root));
        assertEq(rootNonce(lender, _root), 1, "nonce must not advance twice");
    }

    /// @dev But a consumed signature cannot resurrect a status the maker has since changed.
    function testSetIsRootRatifiedWithSigReplayAfterStatusChange() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);

        vm.prank(lender);
        setterRateRatifier.setIsRootRatified(lender, _root, false);

        vm.expectRevert(ISetterRateRatifier.RatifiedStatusChanged.selector);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
        assertFalse(setterRateRatifier.isRootRatified(lender, _root));
    }

    function testSetIsRootRatifiedWithSigCanUnratify() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);

        (v, r, s) = ratifySig(lender, _root, false, 1, vm.getBlockTimestamp(), privateKey[lender]);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, false, 1, vm.getBlockTimestamp(), v, r, s);

        assertFalse(setterRateRatifier.isRootRatified(lender, _root));
        assertEq(rootNonce(lender, _root), 2);
    }

    function testSetIsRootRatifiedWithSigEcrecoverReturnsZero() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, deadline, privateKey[lender]);

        // Valid v values are 27 and 28.
        vm.expectRevert(ISetterRateRatifier.InvalidSignature.selector);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, 0, r, s);
    }

    function testSetIsRootRatifiedWithSigStaleNonceChecksSignature() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, deadline, privateKey[lender]);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, v, r, s);

        // Garbage signature.
        vm.expectRevert(ISetterRateRatifier.InvalidSignature.selector);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, 0, bytes32(0), bytes32(0));

        // Signature from an account the maker never authorized.
        (v, r, s) = ratifySig(lender, _root, true, 0, deadline, privateKey[borrower]);
        vm.expectRevert(ISetterRateRatifier.Unauthorized.selector);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, v, r, s);

        assertTrue(setterRateRatifier.isRootRatified(lender, _root));
        assertEq(rootNonce(lender, _root), 1);
    }

    function testSetIsRootRatifiedWithSigRejectsTampering() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, deadline, privateKey[lender]);

        // Wrong maker.
        vm.expectRevert(ISetterRateRatifier.Unauthorized.selector);
        setterRateRatifier.setIsRootRatifiedWithSig(borrower, _root, true, 0, deadline, v, r, s);

        // Wrong root.
        vm.expectRevert(ISetterRateRatifier.Unauthorized.selector);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, keccak256("other"), true, 0, deadline, v, r, s);

        // Wrong status.
        vm.expectRevert(ISetterRateRatifier.Unauthorized.selector);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, false, 0, deadline, v, r, s);

        // Wrong nonce, checked after the signature so it does not surface as InvalidNonce.
        vm.expectRevert(ISetterRateRatifier.Unauthorized.selector);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 1, deadline, v, r, s);

        // Wrong deadline.
        vm.expectRevert(ISetterRateRatifier.Unauthorized.selector);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline + 1, v, r, s);

        assertFalse(setterRateRatifier.isRootRatified(lender, _root));
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

        vm.expectRevert(ISetterRateRatifier.Unauthorized.selector);
        setterRateRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, v, r, s);
    }
}
