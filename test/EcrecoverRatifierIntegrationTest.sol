// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {IEcrecoverRatifier, Signature} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
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
        market.maturity = block.timestamp + 100;
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
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = MAX_TICK;
    }

    function testTakeInvalidRoot(bytes32 invalidRoot) public {
        vm.assume(invalidRoot != root([lenderOffer]));
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        vm.prank(borrower);
        midnight.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            merkleRatifierData(lenderOffer, 0, invalidRoot, 0, new bytes32[](0))
        );
    }

    function testTakeInvalidSignature() public {
        vm.expectRevert(IEcrecoverRatifier.InvalidSignature.selector);
        Signature memory _sig = Signature({v: 1, r: 0, s: 0});
        vm.prank(borrower);
        midnight.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            abi.encode(_sig, 0, root([lenderOffer]), 0, new bytes32[](0))
        );
    }

    function testTakeInvalidProofOneLeaf(bytes32[] memory _proof) public {
        vm.assume(_proof.length >= 1);
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        vm.prank(borrower);
        midnight.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            merkleRatifierData(lenderOffer, 0, root([lenderOffer]), 0, _proof)
        );
    }

    function testTakeInvalidProof2LeavesWrongLeafHash(Offer memory otherOffer, bytes32[] memory _proof) public {
        vm.assume(_proof.length >= 1);
        vm.assume(_proof[0] != HashLib.hashOffer(otherOffer));
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        vm.prank(borrower);
        midnight.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            merkleRatifierData(lenderOffer, 1, root([lenderOffer, otherOffer]), 0, _proof)
        );
    }

    function testTakeInvalidProof2LeavesWrongLeafIndex(Offer memory otherOffer) public {
        bytes32[] memory _proof = new bytes32[](1);
        _proof[0] = HashLib.hashOffer(otherOffer);
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        vm.prank(borrower);
        midnight.take(
            100,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            merkleRatifierData(lenderOffer, 1, root([lenderOffer, otherOffer]), 1, _proof)
        );
    }

    function testTakeTwoLeaves(uint256 units, Offer memory otherOffer) public {
        units = bound(units, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(lenderOffer.tick);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(market, borrower, units);
        lenderOffer.maxUnits = units;

        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            address(0),
            hex"",
            borrower,
            lenderOffer,
            merkleRatifierData(lenderOffer, 1, root([lenderOffer, otherOffer]), 0, proof([lenderOffer, otherOffer]))
        );
    }

    function testTakeFourLeaves(uint256 units, uint256 saltTimestamp1, uint256 saltTimestamp2, uint256 saltTimestamp3)
        public
    {
        units = bound(units, 0, maxAssets);
        uint256 price = TickLib.tickToPrice(lenderOffer.tick);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));
        collateralize(market, borrower, units);
        lenderOffer.maxUnits = units;

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
            units,
            borrower,
            address(0),
            hex"",
            borrower,
            offer0,
            merkleRatifierData(
                offer0, 2, root([offer0, offer1, offer2, offer3]), 0, proofFirstLeaf([offer0, offer1, offer2, offer3])
            )
        );

        vm.revertToState(snapshot);
        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            address(0),
            hex"",
            borrower,
            offer1,
            merkleRatifierData(
                offer1, 2, root([offer0, offer1, offer2, offer3]), 1, proofSecondLeaf([offer0, offer1, offer2, offer3])
            )
        );

        vm.revertToState(snapshot);
        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            address(0),
            hex"",
            borrower,
            offer2,
            merkleRatifierData(
                offer2, 2, root([offer0, offer1, offer2, offer3]), 2, proofThirdLeaf([offer0, offer1, offer2, offer3])
            )
        );

        vm.revertToState(snapshot);
        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            address(0),
            hex"",
            borrower,
            offer3,
            merkleRatifierData(
                offer3, 2, root([offer0, offer1, offer2, offer3]), 3, proofFourthLeaf([offer0, offer1, offer2, offer3])
            )
        );
    }

    function testTakeNotRatified() public {
        vm.expectRevert();
        vm.prank(borrower);
        midnight.take(100, borrower, address(0), hex"", borrower, lenderOffer, emptySig);
    }

    function testTakeOfferValidSignature(uint256 makerSecretKey, address sender) public {
        vm.assume(sender != address(0));
        makerSecretKey = boundPrivateKey(makerSecretKey);
        privateKey[vm.addr(makerSecretKey)] = makerSecretKey;
        lenderOffer.maker = vm.addr(makerSecretKey);
        vm.assume(sender != vm.addr(makerSecretKey));
        vm.prank(vm.addr(makerSecretKey));
        midnight.setIsAuthorized(vm.addr(makerSecretKey), address(ecrecoverRatifier), true);
        vm.prank(sender);
        midnight.take(0, sender, address(0), hex"", sender, lenderOffer, merkleRatifierData([lenderOffer]));
    }

    function testOfferAuthorization(uint256 makerSecretKey, address sender, uint256 otherSecretKey) public {
        makerSecretKey = boundPrivateKey(makerSecretKey);
        otherSecretKey = boundPrivateKey(otherSecretKey);
        vm.assume(otherSecretKey != makerSecretKey);
        privateKey[vm.addr(makerSecretKey)] = makerSecretKey;
        privateKey[vm.addr(otherSecretKey)] = otherSecretKey;

        lenderOffer.maker = vm.addr(makerSecretKey);
        vm.prank(vm.addr(makerSecretKey));
        midnight.setIsAuthorized(vm.addr(makerSecretKey), address(ecrecoverRatifier), true);

        vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
        vm.prank(sender);
        midnight.take(
            100,
            sender,
            address(0),
            hex"",
            sender,
            lenderOffer,
            merkleRatifierData([lenderOffer], vm.addr(otherSecretKey))
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

        midnight.setIsAuthorized(vm.addr(makerSecretKey), address(ecrecoverRatifier), true);
        vm.prank(lenderOffer.maker);
        midnight.setIsAuthorized(lenderOffer.maker, vm.addr(otherSecretKey), true);
        vm.prank(sender);
        midnight.take(
            0,
            sender,
            address(0),
            hex"",
            sender,
            lenderOffer,
            merkleRatifierData([lenderOffer], vm.addr(otherSecretKey))
        );
    }
}
