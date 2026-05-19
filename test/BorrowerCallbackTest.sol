// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {WAD, LLTV_2} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {BorrowerCallback, CollateralData} from "../src/periphery/BorrowerCallback.sol";

import {BaseTest} from "./BaseTest.sol";
import {ERC20} from "./erc20s/ERC20.sol";

contract BorrowerCallbackTest is BaseTest {
    using UtilsLib for uint256;

    BorrowerCallback internal borrowerCallback;
    Market internal obligation;
    bytes32 internal id;
    Offer internal borrowerOffer;

    function setUp() public override {
        super.setUp();

        borrowerCallback = new BorrowerCallback(address(midnight));

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: LLTV_2,
                    maxLif: maxLif(LLTV_2, 0.25e18),
                    oracle: address(oracle1)
                })
            );
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: LLTV_2,
                    maxLif: maxLif(LLTV_2, 0.25e18),
                    oracle: address(oracle2)
                })
            );
        obligation.collateralParams = sortCollateralParams(obligation.collateralParams);
        obligation.rcfThreshold = 0;

        id = toId(obligation);

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.maxUnits = type(uint256).max;
        borrowerOffer.market = obligation;
        borrowerOffer.ratifier = address(ecrecoverRatifier);
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = MAX_TICK;
    }

    function testConstructor() public view {
        assertEq(borrowerCallback.MIDNIGHT(), address(midnight));
    }

    function testOnSellSingleCollateralMaker(uint256 units) public {
        units = bound(units, 1, 1e33);
        uint256 collateral = units.mulDivUp(WAD, obligation.collateralParams[0].lltv);

        borrowerOffer.callback = address(borrowerCallback);
        CollateralData[] memory collateralData = new CollateralData[](1);
        collateralData[0] = CollateralData({collateralIndex: 0, amount: collateral});
        borrowerOffer.callbackData = abi.encode(collateralData);
        borrowerOffer.maxUnits = units;

        // Fund lender with loan tokens.
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));

        // Fund callback with collateral tokens and approve midnight.
        deal(obligation.collateralParams[0].token, address(borrowerCallback), collateral);
        vm.prank(address(borrowerCallback));
        ERC20(obligation.collateralParams[0].token).approve(address(midnight), collateral);

        // Authorize callback to supply collateral on behalf of borrower.
        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, address(borrowerCallback), true);

        assertEq(midnight.collateral(id, borrower, 0), 0);

        take(units, lender, borrowerOffer);

        assertEq(midnight.collateral(id, borrower, 0), collateral);
    }

    function testOnSellMultipleCollateralsMaker(uint256 units) public {
        units = bound(units, 1, 1e33);
        uint256 collateral0 = units.mulDivUp(WAD, obligation.collateralParams[0].lltv);
        uint256 collateral1 = units.mulDivUp(WAD, obligation.collateralParams[1].lltv);

        borrowerOffer.callback = address(borrowerCallback);
        CollateralData[] memory collateralData = new CollateralData[](2);
        collateralData[0] = CollateralData({collateralIndex: 0, amount: collateral0});
        collateralData[1] = CollateralData({collateralIndex: 1, amount: collateral1});
        borrowerOffer.callbackData = abi.encode(collateralData);
        borrowerOffer.maxUnits = units;

        // Fund lender with loan tokens.
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));

        // Fund callback with collateral tokens and approve midnight.
        deal(obligation.collateralParams[0].token, address(borrowerCallback), collateral0);
        deal(obligation.collateralParams[1].token, address(borrowerCallback), collateral1);
        vm.prank(address(borrowerCallback));
        ERC20(obligation.collateralParams[0].token).approve(address(midnight), collateral0);
        vm.prank(address(borrowerCallback));
        ERC20(obligation.collateralParams[1].token).approve(address(midnight), collateral1);

        // Authorize callback to supply collateral on behalf of borrower.
        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, address(borrowerCallback), true);

        assertEq(midnight.collateral(id, borrower, 0), 0);
        assertEq(midnight.collateral(id, borrower, 1), 0);

        take(units, lender, borrowerOffer);

        assertEq(midnight.collateral(id, borrower, 0), collateral0);
        assertEq(midnight.collateral(id, borrower, 1), collateral1);
    }

    function testOnSellTaker(uint256 units) public {
        units = bound(units, 1, 1e33);
        uint256 collateral = units.mulDivUp(WAD, obligation.collateralParams[0].lltv);

        // Lender makes a buy offer.
        Offer memory lenderOffer;
        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.maxUnits = units;
        lenderOffer.market = obligation;
        lenderOffer.ratifier = address(ecrecoverRatifier);
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = MAX_TICK;

        // Fund lender with loan tokens.
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));

        // Fund callback with collateral tokens and approve midnight.
        deal(obligation.collateralParams[0].token, address(borrowerCallback), collateral);
        vm.prank(address(borrowerCallback));
        ERC20(obligation.collateralParams[0].token).approve(address(midnight), collateral);

        // Authorize callback to supply collateral on behalf of borrower.
        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, address(borrowerCallback), true);

        CollateralData[] memory collateralData = new CollateralData[](1);
        collateralData[0] = CollateralData({collateralIndex: 0, amount: collateral});

        assertEq(midnight.collateral(id, borrower, 0), 0);

        // Borrower takes the lender's buy offer, passing BorrowerCallback as taker callback.
        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            address(borrowerCallback),
            abi.encode(collateralData),
            borrower,
            lenderOffer,
            merkleRatifierData([lenderOffer])
        );

        assertEq(midnight.collateral(id, borrower, 0), collateral);
    }

    function testOnSellUnauthorized() public {
        Market memory ob;
        vm.prank(makeAddr("attacker"));
        vm.expectRevert("unauthorized");
        borrowerCallback.onSell(bytes32(0), ob, address(0), 0, 0, "");
    }
}
