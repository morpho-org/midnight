// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {HashLib} from "../src/ratifiers/HashLib.sol";
import {Offer} from "../src/interfaces/IMidnight.sol";
import {OFFER_TYPEHASH} from "../src/libraries/ConstantsLib.sol";

contract HashLibTest is Test {
    function testHashOfferMatchesReference(Offer memory offer) public pure {
        /// Equivalent to HashLib.hashOffer but does not compile under Certora's mode (stack-too-deep).
        bytes32 expectedHash = keccak256(
            abi.encode(
                OFFER_TYPEHASH,
                HashLib.hashObligation(offer.obligation),
                offer.buy,
                offer.maker,
                offer.start,
                offer.expiry,
                offer.tick,
                offer.group,
                offer.session,
                offer.callback,
                keccak256(offer.callbackData),
                offer.receiverIfMakerIsSeller,
                offer.ratifier,
                offer.reduceOnly,
                offer.maxUnits,
                offer.maxSellerAssets,
                offer.maxBuyerAssets
            )
        );
        assertEq(HashLib.hashOffer(offer), expectedHash);
    }
}
