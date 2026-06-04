// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Offer} from "../src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS, WAD} from "../src/libraries/ConstantsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";
import {RateRatifier} from "../src/ratifiers/RateRatifier.sol";
import {IRateRatifier, RATE_OFFER_TYPEHASH} from "../src/ratifiers/interfaces/IRateRatifier.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {BaseTest} from "./BaseTest.sol";
import {COLLATERAL_PARAMS_TYPE, MARKET_TYPE} from "./HashLibTest.sol";

bytes constant RATE_OFFER_TYPE =
    "RateOffer(Market market,bool buy,address maker,uint256 start,uint256 expiry,uint256 rate,bytes32 group,address callback,bytes callbackData,address receiverIfMakerIsSeller,address ratifier,bool reduceOnly,uint256 maxUnits,uint256 maxAssets)";

contract RateRatifierTest is BaseTest {
    RateRatifier internal rateRatifier;

    function setUp() public override {
        super.setUp();
        rateRatifier = new RateRatifier(address(midnight));
        vm.prank(lender);
        midnight.setIsAuthorized(address(rateRatifier), true, lender);
        vm.prank(borrower);
        midnight.setIsAuthorized(address(rateRatifier), true, borrower);
    }

    function testRateOfferTypeHash() public pure {
        assertEq(RATE_OFFER_TYPEHASH, keccak256(bytes.concat(RATE_OFFER_TYPE, COLLATERAL_PARAMS_TYPE, MARKET_TYPE)));
    }

    function rateSignature(Offer memory offer, uint256 rate, uint256 _privateKey)
        internal
        view
        returns (Signature memory sig)
    {
        bytes32 structHash = HashLib.hashRateOffer(offer, rate);
        bytes32 sep = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(rateRatifier)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", sep, structHash));
        (sig.v, sig.r, sig.s) = vm.sign(_privateKey, digest);
    }

    function buildRatifierData(Offer memory offer, uint256 rate, address signer) internal view returns (bytes memory) {
        return abi.encode(rateSignature(offer, rate, privateKey[signer]), rate);
    }

    /// @dev Returns an offer with 1 year to maturity and the ratifier wired up.
    function makeOffer(address maker, bool buy) internal view returns (Offer memory offer) {
        offer.maker = maker;
        offer.buy = buy;
        offer.ratifier = address(rateRatifier);
        offer.expiry = block.timestamp + 365 days;
        offer.market.maturity = block.timestamp + 365 days;
    }

    /// @dev Per-second WAD rate giving ~10% over 1 year via simple interest: rate = 0.1e18 / 365 days.
    function rate10pct() internal pure returns (uint256) {
        return uint256(0.1e18) / 365 days;
    }

    function testIsRatifiedBuyer() public {
        Offer memory offer = makeOffer(lender, true);
        uint256 rate = rate10pct();
        // priceLimit ~ WAD / 1.1 ~ 0.909e18. tick=0 -> price ~ 0, well below: OK.
        offer.tick = 0;
        bytes memory data = buildRatifierData(offer, rate, lender);

        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data), CALLBACK_SUCCESS);
    }

    function testIsRatifiedSeller() public {
        Offer memory offer = makeOffer(borrower, false);
        uint256 rate = rate10pct();
        offer.tick = MAX_TICK; // highest price, clearly >= priceLimit.
        bytes memory data = buildRatifierData(offer, rate, borrower);

        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data), CALLBACK_SUCCESS);
    }

    function testIsRatifiedAuthorizedSigner() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);

        bytes memory data = buildRatifierData(offer, rate, borrower);
        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data), CALLBACK_SUCCESS);
    }

    function testIsRatifiedNotMidnight() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        bytes memory data = buildRatifierData(offer, rate10pct(), lender);

        vm.expectRevert(IRateRatifier.NotMidnight.selector);
        rateRatifier.isRatified(offer, data);
    }

    function testIsRatifiedUnauthorizedSigner() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        bytes memory data = buildRatifierData(offer, rate10pct(), borrower);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifier.Unauthorized.selector);
        rateRatifier.isRatified(offer, data);
    }

    function testIsRatifiedInvalidSignature() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        bytes memory data = abi.encode(Signature({v: 27, r: bytes32(uint256(1)), s: bytes32(uint256(2))}), rate10pct());

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifier.Unauthorized.selector);
        rateRatifier.isRatified(offer, data);
    }

    function testWorsePriceBuyer() public {
        Offer memory offer = makeOffer(lender, true);
        uint256 rate = rate10pct();
        // priceLimit ~ 0.909e18. MAX_TICK gives ~WAD which is way above the limit -> revert.
        offer.tick = MAX_TICK;
        bytes memory data = buildRatifierData(offer, rate, lender);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifier.WorsePrice.selector);
        rateRatifier.isRatified(offer, data);
    }

    function testWorsePriceSeller() public {
        Offer memory offer = makeOffer(borrower, false);
        uint256 rate = rate10pct();
        // priceLimit ~ 0.909e18. tick=0 gives ~0 which is far below the floor -> revert.
        offer.tick = 0;
        bytes memory data = buildRatifierData(offer, rate, borrower);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifier.WorsePrice.selector);
        rateRatifier.isRatified(offer, data);
    }

    function testRateZeroBuyerAcceptsAnyTick() public {
        Offer memory offer = makeOffer(lender, true);
        // rate = 0 -> priceLimit = WAD. tickToPrice <= WAD always, so any tick is acceptable.
        offer.tick = MAX_TICK;
        bytes memory data = buildRatifierData(offer, 0, lender);

        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data), CALLBACK_SUCCESS);
    }

    function testTimeProgressRelaxesBuyerLimit() public {
        Offer memory offer = makeOffer(lender, true);
        uint256 rate = rate10pct();
        // Pick a tick whose price sits between priceLimit(1 year) and priceLimit(0.5 year).
        // priceLimit(1y) ~ 0.909e18, priceLimit(0.5y) ~ 0.952e18.
        uint256 _tick = TickLib.priceToTick(0.93e18, 1);
        offer.tick = _tick;
        bytes memory data = buildRatifierData(offer, rate, lender);

        // At t=0 the offer is above the buyer's limit -> revert.
        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifier.WorsePrice.selector);
        rateRatifier.isRatified(offer, data);

        // Half a year later the limit has grown enough to accept the same tick.
        vm.warp(block.timestamp + 182 days);
        vm.prank(address(midnight));
        assertEq(rateRatifier.isRatified(offer, data), CALLBACK_SUCCESS);
    }

    function testRevokeAuthorizationInvalidates() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        uint256 rate = rate10pct();

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, true, lender);
        bytes memory data = buildRatifierData(offer, rate, borrower);

        vm.prank(address(midnight));
        rateRatifier.isRatified(offer, data);

        vm.prank(lender);
        midnight.setIsAuthorized(borrower, false, lender);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifier.Unauthorized.selector);
        rateRatifier.isRatified(offer, data);
    }

    function testTamperedRateInRatifierData() public {
        Offer memory offer = makeOffer(lender, true);
        offer.tick = 0;
        // Sign at one rate, submit a different rate in ratifierData -> signature mismatch.
        Signature memory sig = rateSignature(offer, rate10pct(), privateKey[lender]);
        bytes memory data = abi.encode(sig, rate10pct() * 2);

        vm.prank(address(midnight));
        vm.expectRevert(IRateRatifier.Unauthorized.selector);
        rateRatifier.isRatified(offer, data);
    }
}
