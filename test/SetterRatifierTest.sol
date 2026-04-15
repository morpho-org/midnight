// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {CollateralParams, Obligation, Offer} from "../src/interfaces/IMidnight.sol";
import {SetterRatifier} from "../src/ratifiers/SetterRatifier.sol";
import {ISetterRatifier} from "../src/ratifiers/interfaces/ISetterRatifier.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {BaseTest} from "./BaseTest.sol";

contract SetterRatifierTest is BaseTest {
    SetterRatifier internal setterRatifier;

    function setUp() public override {
        super.setUp();
        setterRatifier = new SetterRatifier(address(midnight));
    }

    function makeOffer(address maker) internal view returns (Offer memory offer) {
        Obligation memory obligation;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collateralParams = new CollateralParams[](1);
        obligation.collateralParams[0] = CollateralParams({
            token: address(collateralToken1), lltv: 0.77e18, maxLif: maxLif(0.77e18, 0.25e18), oracle: address(oracle1)
        });

        offer.obligation = obligation;
        offer.buy = true;
        offer.maker = maker;
        offer.ratifier = address(setterRatifier);
        offer.maxUnits = type(uint256).max;
        offer.expiry = block.timestamp + 200;
        offer.tick = MAX_TICK;
    }

    function testSetIsRatifiedMaker() public {
        bytes32 _root = keccak256("root");

        vm.prank(lender);
        setterRatifier.setIsRatified(lender, _root, true);

        assertTrue(setterRatifier.isRatified(lender, _root));
    }

    function testOnRatifyAuthorizedSetterCanRatifyOnBehalf() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = keccak256(abi.encode(offer));

        vm.prank(lender);
        midnight.setIsAuthorized(lender, borrower, true);

        vm.prank(borrower);
        setterRatifier.setIsRatified(lender, _root, true);

        bytes32 result = setterRatifier.onRatify(offer, _root, "");
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testTakeAuthorizedSetterCanRatifyOnBehalf() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = keccak256(abi.encode(offer));

        vm.prank(lender);
        midnight.setIsAuthorized(lender, address(setterRatifier), true);
        vm.prank(lender);
        midnight.setIsAuthorized(lender, borrower, true);

        vm.prank(borrower);
        setterRatifier.setIsRatified(lender, _root, true);

        vm.prank(borrower);
        midnight.take(0, borrower, address(0), hex"", borrower, offer, emptySig, _root, proof([offer]));
    }

    function testSetIsRatifiedUnauthorizedOnBehalf() public {
        bytes32 _root = keccak256("root");

        vm.prank(borrower);
        vm.expectRevert(ISetterRatifier.Unauthorized.selector);
        setterRatifier.setIsRatified(lender, _root, true);
    }
}
