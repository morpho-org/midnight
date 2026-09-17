// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {CollateralParams, Market, Offer} from "../src/interfaces/IMidnight.sol";
import {PriceRatifierV1} from "../src/ratifiers/PriceRatifierV1.sol";
import {IPriceRatifierV1} from "../src/ratifiers/interfaces/IPriceRatifierV1.sol";
import {SET_IS_ROOT_RATIFIED_SUCCESS} from "../src/ratifiers/interfaces/IRatifiersV1Common.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

contract PriceRatifierV1Test is BaseTest {
    PriceRatifierV1 internal priceRatifier;

    function setUp() public override {
        super.setUp();
        priceRatifier = new PriceRatifierV1(address(midnight));

        vm.prank(lender);
        midnight.setIsAuthorized(address(this), true, lender);
        vm.prank(borrower);
        midnight.setIsAuthorized(address(this), true, borrower);
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
        offer.ratifier = address(priceRatifier);
        offer.maxUnits = type(uint128).max;
        offer.expiry = vm.getBlockTimestamp() + 200;
        offer.tick = MAX_TICK;
    }

    function testSetIsRootRatifiedMaker() public {
        bytes32 _root = keccak256("root");

        vm.expectEmit();
        emit IPriceRatifierV1.SetIsRootRatified(lender, lender, _root, true);

        vm.prank(lender);
        assertEq(priceRatifier.setIsRootRatified(lender, _root, true), SET_IS_ROOT_RATIFIED_SUCCESS);

        assertTrue(priceRatifier.isRootRatified(lender, _root));
    }

    function testIsRatifiedAuthorizedSetterCanRatifyOnBehalf() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashPriceRatifierV1Offer(offer, address(0));

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        vm.prank(borrower);
        priceRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        bytes32 result = priceRatifier.isRatified(offer, abi.encode(_root, 0, new bytes32[](0), address(0)), address(0));
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testTakeAuthorizedSetterCanRatifyOnBehalf() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashPriceRatifierV1Offer(offer, address(0));

        vm.prank(lender);
        midnight.setIsAuthorized(address(priceRatifier), true, lender);
        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        vm.prank(borrower);
        priceRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(borrower);
        midnight.take(
            offer, abi.encode(_root, 0, new bytes32[](0), address(0)), 0, borrower, borrower, address(0), hex""
        );
    }

    function testIsRatifiedUsesLeafIndex() public {
        Offer memory leftOffer = makeOffer(lender);
        Offer memory rightOffer = makeOffer(lender);
        rightOffer.expiry += 1;

        bytes32 _root = HashLib.hashNode(
            HashLib.hashPriceRatifierV1Offer(leftOffer, address(0)),
            HashLib.hashPriceRatifierV1Offer(rightOffer, address(0))
        );
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = HashLib.hashPriceRatifierV1Offer(leftOffer, address(0));

        vm.prank(lender);
        priceRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        vm.expectRevert(IPriceRatifierV1.InvalidProof.selector);
        priceRatifier.isRatified(rightOffer, abi.encode(_root, 0, proof, address(0)), address(0));

        vm.prank(address(midnight));
        bytes32 result = priceRatifier.isRatified(rightOffer, abi.encode(_root, 1, proof, address(0)), address(0));
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testSetIsRootRatifiedUnauthorizedOnBehalf() public {
        bytes32 _root = keccak256("root");

        vm.prank(borrower);
        vm.expectRevert(IPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatified(lender, _root, true);
    }

    function testAllowedTaker() public {
        Offer memory offer = makeOffer(lender);
        address allowedTaker = borrower;

        bytes32 _root = HashLib.hashPriceRatifierV1Offer(offer, allowedTaker);
        vm.prank(lender);
        priceRatifier.setIsRootRatified(lender, _root, true);

        bytes memory data = abi.encode(_root, uint256(0), new bytes32[](0), allowedTaker);

        vm.prank(address(midnight));
        vm.expectRevert(IPriceRatifierV1.UnauthorizedTaker.selector);
        priceRatifier.isRatified(offer, data, otherBorrower);

        vm.prank(address(midnight));
        assertEq(priceRatifier.isRatified(offer, data, allowedTaker), CALLBACK_SUCCESS);

        // Being authorized by `allowedTaker` is not enough: the taker itself must be `allowedTaker`.
        vm.prank(allowedTaker);
        midnight.setIsAuthorized(otherBorrower, true, allowedTaker);

        vm.prank(address(midnight));
        vm.expectRevert(IPriceRatifierV1.UnauthorizedTaker.selector);
        priceRatifier.isRatified(offer, data, otherBorrower);
    }

    function testTamperedAllowedTakerInRatifierData() public {
        Offer memory offer = makeOffer(lender);
        address allowedTaker = borrower;

        bytes32 _root = HashLib.hashPriceRatifierV1Offer(offer, allowedTaker);
        vm.prank(lender);
        priceRatifier.setIsRootRatified(lender, _root, true);

        bytes memory data = abi.encode(_root, uint256(0), new bytes32[](0), allowedTaker);
        bytes memory tamperedData = abi.encode(_root, uint256(0), new bytes32[](0), address(0));

        vm.prank(address(midnight));
        vm.expectRevert(IPriceRatifierV1.InvalidProof.selector);
        priceRatifier.isRatified(offer, tamperedData, otherBorrower);

        vm.prank(address(midnight));
        assertEq(priceRatifier.isRatified(offer, data, allowedTaker), CALLBACK_SUCCESS);
    }

    /// @dev The signed typehash depends on the height of the offer tree the root commits to.
    function ratifySig(
        address maker,
        bytes32 _root,
        uint256 height,
        bool newIsRootRatified,
        uint128 nonce,
        uint256 deadline,
        uint256 _privateKey
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 hashStruct = keccak256(
            abi.encode(
                HashLib.priceRatifierV1OfferTreeTypeHash(height), maker, _root, newIsRootRatified, nonce, deadline
            )
        );
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator(address(priceRatifier)), hashStruct));
        (v, r, s) = vm.sign(_privateKey, digest);
    }

    function ratifySigSingleOffer(
        address maker,
        bytes32 _root,
        bool newIsRootRatified,
        uint128 nonce,
        uint256 deadline,
        uint256 _privateKey
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        return ratifySig(maker, _root, 0, newIsRootRatified, nonce, deadline, _privateKey);
    }

    function testDomainSeparator() public view {
        bytes32 expected = vm.eip712HashStruct(
            "EIP712Domain(uint256 chainId,address verifyingContract)", abi.encode(block.chainid, address(priceRatifier))
        );
        assertEq(priceRatifier.DOMAIN_SEPARATOR(), expected);
    }

    function testSetIsRootRatifiedWithSig() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashPriceRatifierV1Offer(offer, address(0));

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySigSingleOffer(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        vm.expectEmit();
        emit IPriceRatifierV1.SetIsRootRatifiedWithSig(borrower, lender, lender, _root, 0, true, 0, 0);

        vm.prank(borrower);
        assertEq(
            priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, vm.getBlockTimestamp(), v, r, s),
            SET_IS_ROOT_RATIFIED_SUCCESS
        );

        assertTrue(priceRatifier.isRootRatified(lender, _root));
        assertEq(priceRatifier.rootNonce(lender, _root), 1);

        vm.prank(address(midnight));
        assertEq(
            priceRatifier.isRatified(offer, abi.encode(_root, 0, new bytes32[](0), address(0)), address(0)),
            CALLBACK_SUCCESS
        );
    }

    function testSetIsRootRatifiedWithSigAuthorizedSigner() public {
        bytes32 _root = keccak256("root");

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySigSingleOffer(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[borrower]);

        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, vm.getBlockTimestamp(), v, r, s);

        assertTrue(priceRatifier.isRootRatified(lender, _root));
    }

    function testSetIsRootRatifiedWithSigUnauthorizedCaller() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySigSingleOffer(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);

        vm.prank(otherBorrower);
        vm.expectRevert(IPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, vm.getBlockTimestamp(), v, r, s);
    }

    function testSetIsRootRatifiedWithSigUnauthorizedSigner() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySigSingleOffer(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[borrower]);

        vm.expectRevert(IPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, vm.getBlockTimestamp(), v, r, s);
    }

    function testSetIsRootRatifiedWithSigDeadlineExpired() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySigSingleOffer(lender, _root, true, 0, deadline, privateKey[lender]);

        vm.warp(deadline + 1);
        vm.expectRevert(IPriceRatifierV1.DeadlineExpired.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, deadline, v, r, s);
    }

    function testSetIsRootRatifiedWithSigNonceTooHigh() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySigSingleOffer(lender, _root, true, 1, vm.getBlockTimestamp(), privateKey[lender]);

        vm.expectRevert(IPriceRatifierV1.InvalidNonce.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 1, vm.getBlockTimestamp(), v, r, s);
    }

    /// @dev Replaying a consumed signature is a no-op while the status it carries still holds, so that a bundle
    /// carrying it twice does not revert.
    function testSetIsRootRatifiedWithSigReplayNoOp() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySigSingleOffer(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);

        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, vm.getBlockTimestamp(), v, r, s);
        assertEq(priceRatifier.rootNonce(lender, _root), 1);

        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, vm.getBlockTimestamp(), v, r, s);
        assertTrue(priceRatifier.isRootRatified(lender, _root));
        assertEq(priceRatifier.rootNonce(lender, _root), 1, "nonce must not advance twice");
    }

    /// @dev But a consumed signature cannot resurrect a status the maker has since changed.
    function testSetIsRootRatifiedWithSigReplayAfterStatusChange() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySigSingleOffer(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, vm.getBlockTimestamp(), v, r, s);

        vm.prank(lender);
        priceRatifier.setIsRootRatified(lender, _root, false);

        vm.expectRevert(IPriceRatifierV1.RatifiedStatusChanged.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, vm.getBlockTimestamp(), v, r, s);
        assertFalse(priceRatifier.isRootRatified(lender, _root));
    }

    function testSetIsRootRatifiedWithSigCanUnratify() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySigSingleOffer(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, vm.getBlockTimestamp(), v, r, s);

        (v, r, s) = ratifySigSingleOffer(lender, _root, false, 1, vm.getBlockTimestamp(), privateKey[lender]);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, false, 1, vm.getBlockTimestamp(), v, r, s);

        assertFalse(priceRatifier.isRootRatified(lender, _root));
        assertEq(priceRatifier.rootNonce(lender, _root), 2);
    }

    function testSetIsRootRatifiedWithSigEcrecoverReturnsZero() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (, bytes32 r, bytes32 s) = ratifySigSingleOffer(lender, _root, true, 0, deadline, privateKey[lender]);

        // Valid v values are 27 and 28.
        vm.expectRevert(IPriceRatifierV1.InvalidSignature.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, deadline, 0, r, s);
    }

    function testSetIsRootRatifiedWithSigStaleNonceChecksSignature() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySigSingleOffer(lender, _root, true, 0, deadline, privateKey[lender]);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, deadline, v, r, s);

        // Garbage signature.
        vm.expectRevert(IPriceRatifierV1.InvalidSignature.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, deadline, 0, bytes32(0), bytes32(0));

        // Signature from an account the maker never authorized.
        (v, r, s) = ratifySigSingleOffer(lender, _root, true, 0, deadline, privateKey[borrower]);
        vm.expectRevert(IPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, deadline, v, r, s);

        assertTrue(priceRatifier.isRootRatified(lender, _root));
        assertEq(priceRatifier.rootNonce(lender, _root), 1);
    }

    function testSetIsRootRatifiedWithSigRejectsTampering() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySigSingleOffer(lender, _root, true, 0, deadline, privateKey[lender]);

        // Wrong maker.
        vm.expectRevert(IPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(borrower, _root, 0, true, 0, deadline, v, r, s);

        // Wrong root.
        vm.expectRevert(IPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, keccak256("other"), 0, true, 0, deadline, v, r, s);

        // Wrong status.
        vm.expectRevert(IPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, false, 0, deadline, v, r, s);

        // Wrong nonce, checked after the signature so it does not surface as InvalidNonce.
        vm.expectRevert(IPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 1, deadline, v, r, s);

        // Wrong deadline.
        vm.expectRevert(IPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, deadline + 1, v, r, s);

        assertFalse(priceRatifier.isRootRatified(lender, _root));
        assertEq(priceRatifier.rootNonce(lender, _root), 0);
    }

    function testSetIsRootRatifiedWithSigRejectsRevokedAuthorization() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        (uint8 v, bytes32 r, bytes32 s) = ratifySigSingleOffer(lender, _root, true, 0, deadline, privateKey[borrower]);

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, false, lender);

        vm.expectRevert(IPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 0, true, 0, deadline, v, r, s);
    }

    function testSetIsRootRatifiedWithSigWrongHeight() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, 1, true, 0, deadline, privateKey[lender]);

        // The height is committed to by the signature, so another one recovers an unrelated signer.
        vm.expectRevert(IPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 2, true, 0, deadline, v, r, s);

        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 1, true, 0, deadline, v, r, s);
        assertTrue(priceRatifier.isRootRatified(lender, _root));
    }

    function testSetIsRootRatifiedWithSigHeightTooHigh() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, 20, true, 0, deadline, privateKey[lender]);

        vm.expectRevert(HashLib.TreeTooHigh.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 21, true, 0, deadline, v, r, s);
    }

    /// @dev Ratifying by signature a tree whose leaves are offers, then taking one of them.
    function testSetIsRootRatifiedWithSigOfferTree() public {
        Offer memory leftOffer = makeOffer(lender);
        Offer memory rightOffer = makeOffer(lender);
        rightOffer.expiry += 1;

        bytes32 leftHash = HashLib.hashPriceRatifierV1Offer(leftOffer, address(0));
        bytes32 rightHash = HashLib.hashPriceRatifierV1Offer(rightOffer, address(0));
        bytes32 _root = HashLib.hashNode(leftHash, rightHash);

        uint256 deadline = vm.getBlockTimestamp();
        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, 1, true, 0, deadline, privateKey[lender]);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, 1, true, 0, deadline, v, r, s);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = rightHash;

        vm.prank(address(midnight));
        bytes32 result =
            priceRatifier.isRatified(leftOffer, abi.encode(_root, uint256(0), proof, address(0)), address(0));
        assertEq(result, CALLBACK_SUCCESS);
    }
}
