// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {CollateralParams, Market, Offer} from "../src/interfaces/IMidnight.sol";
import {PriceRatifier} from "../src/ratifiers/PriceRatifier.sol";
import {IPriceRatifier} from "../src/ratifiers/interfaces/IPriceRatifier.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

contract PriceRatifierTest is BaseTest {
    PriceRatifier internal priceRatifier;

    function setUp() public override {
        super.setUp();
        priceRatifier = new PriceRatifier(address(midnight));

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

    /// @dev The status and the nonce share a slot, so they come back as a tuple from the generated getter.
    function rootNonce(address maker, bytes32 root) internal view returns (uint128) {
        (, uint128 nonce) = priceRatifier.ratification(maker, root);
        return nonce;
    }

    function testSetIsRootRatifiedMaker() public {
        bytes32 _root = keccak256("root");

        vm.expectEmit();
        emit IPriceRatifier.SetIsRootRatified(lender, lender, _root, true);

        vm.prank(lender);
        priceRatifier.setIsRootRatified(lender, _root, true);

        assertTrue(priceRatifier.isRootRatified(lender, _root));
    }

    function testIsRatifiedAuthorizedSetterCanRatifyOnBehalf() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        vm.prank(borrower);
        priceRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        bytes32 result = priceRatifier.isRatified(offer, abi.encode(_root, 0, new bytes32[](0)), address(0));
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testTakeAuthorizedSetterCanRatifyOnBehalf() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);

        vm.prank(lender);
        midnight.setIsAuthorized(address(priceRatifier), true, lender);
        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        vm.prank(borrower);
        priceRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(borrower);
        midnight.take(offer, abi.encode(_root, 0, new bytes32[](0)), 0, borrower, borrower, address(0), hex"");
    }

    function testIsRatifiedUsesLeafIndex() public {
        Offer memory leftOffer = makeOffer(lender);
        Offer memory rightOffer = makeOffer(lender);
        rightOffer.expiry += 1;

        bytes32 _root = HashLib.hashNode(HashLib.hashOffer(leftOffer), HashLib.hashOffer(rightOffer));
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = HashLib.hashOffer(leftOffer);

        vm.prank(lender);
        priceRatifier.setIsRootRatified(lender, _root, true);

        vm.prank(address(midnight));
        vm.expectRevert(IPriceRatifier.InvalidProof.selector);
        priceRatifier.isRatified(rightOffer, abi.encode(_root, 0, proof), address(0));

        vm.prank(address(midnight));
        bytes32 result = priceRatifier.isRatified(rightOffer, abi.encode(_root, 1, proof), address(0));
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testSetIsRootRatifiedUnauthorizedOnBehalf() public {
        bytes32 _root = keccak256("root");

        vm.prank(borrower);
        vm.expectRevert(IPriceRatifier.Unauthorized.selector);
        priceRatifier.setIsRootRatified(lender, _root, true);
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
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator(address(priceRatifier)), hashStruct));
        (v, r, s) = vm.sign(_privateKey, digest);
    }

    function testDomainSeparator() public view {
        bytes32 expected = vm.eip712HashStruct(
            "EIP712Domain(uint256 chainId,address verifyingContract)", abi.encode(block.chainid, address(priceRatifier))
        );
        assertEq(priceRatifier.DOMAIN_SEPARATOR(), expected);
    }

    function testSetIsRootRatifiedWithSig() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = HashLib.hashOffer(offer);

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        vm.expectEmit();
        emit IPriceRatifier.SetIsRootRatifiedWithSig(lender, lender, _root, true, 0, 0);

        vm.prank(borrower);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);

        assertTrue(priceRatifier.isRootRatified(lender, _root));
        assertEq(rootNonce(lender, _root), 1);

        vm.prank(address(midnight));
        assertEq(priceRatifier.isRatified(offer, abi.encode(_root, 0, new bytes32[](0)), address(0)), CALLBACK_SUCCESS);
    }

    function testSetIsRootRatifiedWithSigAuthorizedSigner() public {
        bytes32 _root = keccak256("root");

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[borrower]);

        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);

        assertTrue(priceRatifier.isRootRatified(lender, _root));
    }

    function testSetIsRootRatifiedWithSigUnauthorizedCaller() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);

        vm.prank(otherBorrower);
        vm.expectRevert(IPriceRatifier.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
    }

    function testSetIsRootRatifiedWithSigUnauthorizedSigner() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) =
            ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[borrower]);

        vm.expectRevert(IPriceRatifier.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
    }

    function testSetIsRootRatifiedWithSigDeadlineExpired() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, deadline, privateKey[lender]);

        vm.warp(deadline + 1);
        vm.expectRevert(IPriceRatifier.DeadlineExpired.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, v, r, s);
    }

    function testSetIsRootRatifiedWithSigNonceTooHigh() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 1, vm.getBlockTimestamp(), privateKey[lender]);

        vm.expectRevert(IPriceRatifier.InvalidNonce.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 1, vm.getBlockTimestamp(), v, r, s);
    }

    /// @dev Replaying a consumed signature is a no-op while the status it carries still holds, so that a bundle
    /// carrying it twice does not revert.
    function testSetIsRootRatifiedWithSigReplayNoOp() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);

        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
        assertEq(rootNonce(lender, _root), 1);

        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
        assertTrue(priceRatifier.isRootRatified(lender, _root));
        assertEq(rootNonce(lender, _root), 1, "nonce must not advance twice");
    }

    /// @dev But a consumed signature cannot resurrect a status the maker has since changed.
    function testSetIsRootRatifiedWithSigReplayAfterStatusChange() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);

        vm.prank(lender);
        priceRatifier.setIsRootRatified(lender, _root, false);

        vm.expectRevert(IPriceRatifier.RatifiedStatusChanged.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);
        assertFalse(priceRatifier.isRootRatified(lender, _root));
    }

    function testSetIsRootRatifiedWithSigCanUnratify() public {
        bytes32 _root = keccak256("root");

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, vm.getBlockTimestamp(), privateKey[lender]);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, vm.getBlockTimestamp(), v, r, s);

        (v, r, s) = ratifySig(lender, _root, false, 1, vm.getBlockTimestamp(), privateKey[lender]);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, false, 1, vm.getBlockTimestamp(), v, r, s);

        assertFalse(priceRatifier.isRootRatified(lender, _root));
        assertEq(rootNonce(lender, _root), 2);
    }

    function testSetIsRootRatifiedWithSigEcrecoverReturnsZero() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, deadline, privateKey[lender]);

        // Valid v values are 27 and 28.
        vm.expectRevert(IPriceRatifier.InvalidSignature.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, 0, r, s);
    }

    function testSetIsRootRatifiedWithSigStaleNonceChecksSignature() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, deadline, privateKey[lender]);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, v, r, s);

        // Garbage signature.
        vm.expectRevert(IPriceRatifier.InvalidSignature.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, 0, bytes32(0), bytes32(0));

        // Signature from an account the maker never authorized.
        (v, r, s) = ratifySig(lender, _root, true, 0, deadline, privateKey[borrower]);
        vm.expectRevert(IPriceRatifier.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, v, r, s);

        assertTrue(priceRatifier.isRootRatified(lender, _root));
        assertEq(rootNonce(lender, _root), 1);
    }

    function testSetIsRootRatifiedWithSigRejectsTampering() public {
        bytes32 _root = keccak256("root");
        uint256 deadline = vm.getBlockTimestamp();

        (uint8 v, bytes32 r, bytes32 s) = ratifySig(lender, _root, true, 0, deadline, privateKey[lender]);

        // Wrong maker.
        vm.expectRevert(IPriceRatifier.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(borrower, _root, true, 0, deadline, v, r, s);

        // Wrong root.
        vm.expectRevert(IPriceRatifier.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, keccak256("other"), true, 0, deadline, v, r, s);

        // Wrong status.
        vm.expectRevert(IPriceRatifier.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, false, 0, deadline, v, r, s);

        // Wrong nonce, checked after the signature so it does not surface as InvalidNonce.
        vm.expectRevert(IPriceRatifier.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 1, deadline, v, r, s);

        // Wrong deadline.
        vm.expectRevert(IPriceRatifier.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline + 1, v, r, s);

        assertFalse(priceRatifier.isRootRatified(lender, _root));
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

        vm.expectRevert(IPriceRatifier.Unauthorized.selector);
        priceRatifier.setIsRootRatifiedWithSig(lender, _root, true, 0, deadline, v, r, s);
    }
}
