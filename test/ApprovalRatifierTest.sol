// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {CollateralParams, Obligation, Offer} from "../src/interfaces/IMidnight.sol";
import {ApprovalRatifier} from "../src/ratifiers/ApprovalRatifier.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {BaseTest} from "./BaseTest.sol";

contract ApprovalRatifierTest is BaseTest {
    ApprovalRatifier internal approvalRatifier;

    function setUp() public override {
        super.setUp();
        approvalRatifier = new ApprovalRatifier(address(midnight));
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
        offer.ratifier = address(approvalRatifier);
        offer.maxUnits = type(uint256).max;
        offer.expiry = block.timestamp + 200;
        offer.tick = MAX_TICK;
    }

    function testSetApprovalMaker() public {
        bytes32 _root = keccak256("root");

        vm.prank(lender);
        approvalRatifier.setApproval(lender, _root, true);

        assertTrue(approvalRatifier.approved(lender, _root));
    }

    function testOnRatifyAuthorizedSetterCanApproveOnBehalf() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = keccak256(abi.encode(offer));

        vm.prank(lender);
        midnight.setIsAuthorized(lender, borrower, true);

        vm.prank(borrower);
        approvalRatifier.setApproval(lender, _root, true);

        bytes32 result = approvalRatifier.onRatify(offer, _root, "");
        assertEq(result, CALLBACK_SUCCESS);
    }

    function testTakeAuthorizedSetterCanApproveOnBehalf() public {
        Offer memory offer = makeOffer(lender);
        bytes32 _root = keccak256(abi.encode(offer));

        vm.prank(lender);
        midnight.setIsAuthorized(lender, address(approvalRatifier), true);
        vm.prank(lender);
        midnight.setIsAuthorized(lender, borrower, true);

        vm.prank(borrower);
        approvalRatifier.setApproval(lender, _root, true);

        vm.prank(borrower);
        midnight.take(0, borrower, address(0), hex"", borrower, offer, emptySig, _root, proof([offer]));
    }

    function testSetApprovalUnauthorizedOnBehalf() public {
        bytes32 _root = keccak256("root");

        vm.prank(borrower);
        vm.expectRevert("unauthorized");
        approvalRatifier.setApproval(lender, _root, true);
    }
}
