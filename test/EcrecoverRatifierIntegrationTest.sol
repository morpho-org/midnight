// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {
    IEcrecoverRatifier,
    Signature,
    EIP712_DOMAIN_TYPEHASH
} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";
import {BaseTest} from "./BaseTest.sol";

/// @dev Tests covering the merkle/signature flow of `EcrecoverRatifier` end-to-end via `Midnight.take`.
/// `EcrecoverRatifierTest` covers the ratifier in isolation; this file pins the integration with Midnight.
contract EcrecoverRatifierIntegrationTest is BaseTest {
    using UtilsLib for uint256;

    Market internal market;
    bytes32 internal id;
    Offer internal lenderOffer;

    uint256 internal maxAssets = 1e33;

    function setUp() public override {
        super.setUp();

        market.loanToken = address(loanToken);
        market.maturity = vm.getBlockTimestamp() + 100;
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        market.collateralParams = sortCollateralParams(market.collateralParams);
        market.rcfThreshold = 0;

        id = toId(market);

        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.ratifier = address(ecrecoverRatifier);
        lenderOffer.maxUnits = type(uint256).max;
        lenderOffer.market = market;
        lenderOffer.expiry = vm.getBlockTimestamp() + 200;
        lenderOffer.tick = MAX_TICK;
    }

    function root(Offer memory offer) internal pure returns (bytes32) {
        return HashLib.hashOffer(offer);
    }

    function root(Offer[1] memory offers) internal pure returns (bytes32) {
        return HashLib.hashOffer(offers[0]);
    }

    function root(Offer[2] memory offers) internal pure returns (bytes32) {
        return HashLib.hashNode(HashLib.hashOffer(offers[0]), HashLib.hashOffer(offers[1]));
    }

    function root(Offer[4] memory offers) internal pure returns (bytes32) {
        bytes32 left = HashLib.hashNode(HashLib.hashOffer(offers[0]), HashLib.hashOffer(offers[1]));
        bytes32 right = HashLib.hashNode(HashLib.hashOffer(offers[2]), HashLib.hashOffer(offers[3]));
        return HashLib.hashNode(left, right);
    }

    function proof(Offer[1] memory) internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function proof(Offer[2] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory _proof = new bytes32[](1);
        _proof[0] = HashLib.hashOffer(offers[1]);
        return _proof;
    }

    // 4 leaves, assumes the offer is the first one
    function proofFirstLeaf(Offer[4] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory _proof = new bytes32[](2);
        _proof[0] = HashLib.hashOffer(offers[1]);
        _proof[1] = HashLib.hashNode(HashLib.hashOffer(offers[2]), HashLib.hashOffer(offers[3]));
        return _proof;
    }

    // 4 leaves, assumes the offer is the second one
    function proofSecondLeaf(Offer[4] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory _proof = new bytes32[](2);
        _proof[0] = HashLib.hashOffer(offers[0]);
        _proof[1] = HashLib.hashNode(HashLib.hashOffer(offers[2]), HashLib.hashOffer(offers[3]));
        return _proof;
    }

    // 4 leaves, assumes the offer is the third one
    function proofThirdLeaf(Offer[4] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory _proof = new bytes32[](2);
        _proof[0] = HashLib.hashOffer(offers[3]);
        _proof[1] = HashLib.hashNode(HashLib.hashOffer(offers[0]), HashLib.hashOffer(offers[1]));
        return _proof;
    }

    // 4 leaves, assumes the offer is the fourth one
    function proofFourthLeaf(Offer[4] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory _proof = new bytes32[](2);
        _proof[0] = HashLib.hashOffer(offers[2]);
        _proof[1] = HashLib.hashNode(HashLib.hashOffer(offers[0]), HashLib.hashOffer(offers[1]));
        return _proof;
    }

    function merkleRatifierData(Offer[1] memory offers, address _signer) internal view returns (bytes memory) {
        bytes32 _root = root(offers);
        bytes32[] memory _proof = proof(offers);
        Signature memory _sig = signature(_root, privateKey[_signer], offers[0].ratifier, _proof.length);
        return abi.encode(_sig, _root, 0, _proof);
    }

    function merkleRatifierData(Offer[1] memory offers) internal view returns (bytes memory) {
        bytes32 _root = root(offers);
        bytes32[] memory _proof = proof(offers);
        Signature memory _sig = signature(_root, privateKey[offers[0].maker], offers[0].ratifier, _proof.length);
        return abi.encode(_sig, _root, 0, _proof);
    }

    /// @dev Builds merkle ratifier data with explicit root, leaf index, and proof — useful for negative tests where
    /// the signed root or the proof is intentionally inconsistent with the offer.
    function merkleRatifierData(Offer memory offer, bytes32 _root, uint256 _leafIndex, bytes32[] memory _proof)
        internal
        view
        returns (bytes memory)
    {
        Signature memory _sig = signature(_root, privateKey[offer.maker], offer.ratifier, _proof.length);
        return abi.encode(_sig, _root, _leafIndex, _proof);
    }

    function testTakeInvalidRoot(bytes32 invalidRoot) public {
        vm.assume(invalidRoot != root([lenderOffer]));
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        vm.prank(borrower);
        midnight.take(
            lenderOffer,
            merkleRatifierData(lenderOffer, invalidRoot, 0, new bytes32[](0)),
            100,
            borrower,
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeInvalidSignature() public {
        vm.expectRevert(IEcrecoverRatifier.InvalidSignature.selector);
        Signature memory _sig = Signature({v: 1, r: 0, s: 0});
        vm.prank(borrower);
        midnight.take(
            lenderOffer,
            abi.encode(_sig, root([lenderOffer]), 0, new bytes32[](0)),
            100,
            borrower,
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeInvalidProofOneLeaf(bytes32[] memory _proof) public {
        vm.assume(_proof.length >= 1 && _proof.length <= 20);
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        vm.prank(borrower);
        midnight.take(
            lenderOffer,
            merkleRatifierData(lenderOffer, root([lenderOffer]), 0, _proof),
            100,
            borrower,
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeInvalidProof2LeavesWrongLeafHash(Offer memory otherOffer, bytes32[] memory _proof) public {
        vm.assume(_proof.length >= 1 && _proof.length <= 20);
        vm.assume(_proof[0] != HashLib.hashOffer(otherOffer));
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        vm.prank(borrower);
        midnight.take(
            lenderOffer,
            merkleRatifierData(lenderOffer, root([lenderOffer, otherOffer]), 0, _proof),
            100,
            borrower,
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeInvalidProof2LeavesWrongLeafIndex(Offer memory otherOffer) public {
        bytes32[] memory _proof = new bytes32[](1);
        _proof[0] = HashLib.hashOffer(otherOffer);
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        vm.prank(borrower);
        midnight.take(
            lenderOffer,
            merkleRatifierData(lenderOffer, root([lenderOffer, otherOffer]), 1, _proof),
            100,
            borrower,
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeTwoLeaves(uint256 units, Offer memory otherOffer) public {
        units = bound(units, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(lenderOffer.tick);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(market, borrower, units);
        lenderOffer.maxUnits = type(uint256).max;

        vm.prank(borrower);
        midnight.take(
            lenderOffer,
            merkleRatifierData(lenderOffer, root([lenderOffer, otherOffer]), 0, proof([lenderOffer, otherOffer])),
            units,
            borrower,
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeFourLeaves(uint256 units, uint256 saltTimestamp1, uint256 saltTimestamp2, uint256 saltTimestamp3)
        public
    {
        units = bound(units, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(lenderOffer.tick);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(market, borrower, units);
        lenderOffer.maxUnits = type(uint256).max;

        Offer memory offer0 = lenderOffer;

        Offer memory offer1 = lenderOffer;
        offer1.expiry += bound(saltTimestamp1, 0, type(uint32).max);

        Offer memory offer2 = lenderOffer;
        offer2.expiry += bound(saltTimestamp2, 0, type(uint32).max);

        Offer memory offer3 = lenderOffer;
        offer3.expiry += bound(saltTimestamp3, 0, type(uint32).max);

        uint256 snapshot = vm.snapshotState();
        vm.prank(borrower);
        midnight.take(
            offer0,
            merkleRatifierData(
                offer0, root([offer0, offer1, offer2, offer3]), 0, proofFirstLeaf([offer0, offer1, offer2, offer3])
            ),
            units,
            borrower,
            borrower,
            address(0),
            hex""
        );

        vm.revertToState(snapshot);
        vm.prank(borrower);
        midnight.take(
            offer1,
            merkleRatifierData(
                offer1, root([offer0, offer1, offer2, offer3]), 1, proofSecondLeaf([offer0, offer1, offer2, offer3])
            ),
            units,
            borrower,
            borrower,
            address(0),
            hex""
        );

        vm.revertToState(snapshot);
        vm.prank(borrower);
        midnight.take(
            offer2,
            merkleRatifierData(
                offer2, root([offer0, offer1, offer2, offer3]), 2, proofThirdLeaf([offer0, offer1, offer2, offer3])
            ),
            units,
            borrower,
            borrower,
            address(0),
            hex""
        );

        vm.revertToState(snapshot);
        vm.prank(borrower);
        midnight.take(
            offer3,
            merkleRatifierData(
                offer3, root([offer0, offer1, offer2, offer3]), 3, proofFourthLeaf([offer0, offer1, offer2, offer3])
            ),
            units,
            borrower,
            borrower,
            address(0),
            hex""
        );
    }

    function testTakeNotRatified() public {
        vm.expectRevert();
        vm.prank(borrower);
        midnight.take(lenderOffer, emptySig, 100, borrower, borrower, address(0), hex"");
    }

    function testTakeOfferValidSignature(uint256 makerSecretKey, address sender) public {
        vm.assume(sender != address(0));
        makerSecretKey = boundPrivateKey(makerSecretKey);
        privateKey[vm.addr(makerSecretKey)] = makerSecretKey;
        lenderOffer.maker = vm.addr(makerSecretKey);
        vm.assume(sender != vm.addr(makerSecretKey));
        vm.prank(vm.addr(makerSecretKey));
        midnight.setIsAuthorized(address(ecrecoverRatifier), true, vm.addr(makerSecretKey));
        vm.prank(sender);
        midnight.take(lenderOffer, merkleRatifierData([lenderOffer]), 0, sender, sender, address(0), hex"");
    }

    function testOfferAuthorization(uint256 makerSecretKey, address sender, uint256 otherSecretKey) public {
        makerSecretKey = boundPrivateKey(makerSecretKey);
        otherSecretKey = boundPrivateKey(otherSecretKey);
        vm.assume(otherSecretKey != makerSecretKey);
        privateKey[vm.addr(makerSecretKey)] = makerSecretKey;
        privateKey[vm.addr(otherSecretKey)] = otherSecretKey;

        lenderOffer.maker = vm.addr(makerSecretKey);
        vm.prank(vm.addr(makerSecretKey));
        midnight.setIsAuthorized(address(ecrecoverRatifier), true, vm.addr(makerSecretKey));

        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        vm.prank(sender);
        midnight.take(
            lenderOffer,
            merkleRatifierData([lenderOffer], vm.addr(otherSecretKey)),
            100,
            sender,
            sender,
            address(0),
            hex""
        );
    }

    function testOfferAuthorizationAuthorizedSigner(uint256 makerSecretKey, address sender, uint256 otherSecretKey)
        public
    {
        vm.assume(sender != address(0));
        makerSecretKey = boundPrivateKey(makerSecretKey);
        otherSecretKey = boundPrivateKey(otherSecretKey);
        vm.assume(otherSecretKey != makerSecretKey);
        privateKey[vm.addr(makerSecretKey)] = makerSecretKey;
        privateKey[vm.addr(otherSecretKey)] = otherSecretKey;

        lenderOffer.maker = vm.addr(makerSecretKey);
        vm.assume(sender != lenderOffer.maker);

        vm.prank(vm.addr(makerSecretKey));
        midnight.setIsAuthorized(address(ecrecoverRatifier), true, vm.addr(makerSecretKey));
        vm.prank(lenderOffer.maker);
        midnight.setIsAuthorized(vm.addr(otherSecretKey), true, lenderOffer.maker);
        vm.prank(sender);
        midnight.take(
            lenderOffer,
            merkleRatifierData([lenderOffer], vm.addr(otherSecretKey)),
            0,
            sender,
            sender,
            address(0),
            hex""
        );
    }
}
