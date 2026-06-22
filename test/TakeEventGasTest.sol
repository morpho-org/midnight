// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {BaseTest} from "./BaseTest.sol";

contract TakeEventGasTest is BaseTest {
    Market internal market;
    Offer internal storedOffer;
    uint256 internal storedUnits;
    address internal storedTaker;
    address internal storedReceiver;
    address internal storedTakerCallback;
    bytes internal storedRatifierData;
    bytes internal storedTakerCallbackData;
    uint256 internal sink;

    function setUp() public override {
        super.setUp();

        market.loanToken = address(loanToken);
        market.maturity = vm.getBlockTimestamp() + 100 days;
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        market.rcfThreshold = 0;

        storedUnits = 1e18;
        storedTaker = borrower;
        storedReceiver = borrower;

        storedOffer.market = market;
        storedOffer.buy = true;
        storedOffer.maker = lender;
        storedOffer.ratifier = address(dummyRatifier);
        storedOffer.maxUnits = type(uint256).max;
        storedOffer.continuousFeeCap = type(uint256).max;
        storedOffer.expiry = vm.getBlockTimestamp() + 100 days;
        storedOffer.tick = MAX_TICK;

        collateralize(market, borrower, storedUnits);
        deal(address(loanToken), lender, storedUnits);
    }

    function testGasTakeSmall() public {
        Offer memory offer = storedOffer;
        bytes memory ratifierData = storedRatifierData;
        uint256 units = storedUnits;
        address taker = storedTaker;
        address receiver = storedReceiver;
        address takerCallback = storedTakerCallback;
        bytes memory takerCallbackData = storedTakerCallbackData;

        vm.prank(taker);
        uint256 gasBefore = gasleft();
        (uint256 buyerAssets, uint256 sellerAssets) =
            midnight.take(offer, ratifierData, units, taker, receiver, takerCallback, takerCallbackData);
        uint256 gasUsed = gasBefore - gasleft();

        sink = buyerAssets + sellerAssets + gasUsed;
        emit log_named_uint("take gas", gasUsed);
    }
}
