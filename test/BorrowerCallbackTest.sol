// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Obligation, Offer, Signature, Collateral} from "../src/interfaces/IMidnight.sol";
import {Midnight} from "../src/Midnight.sol";
import {WAD, ORACLE_PRICE_SCALE} from "../src/libraries/ConstantsLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {TickLib, MAX_TICK} from "../src/libraries/TickLib.sol";
import {BorrowerCallback, CollateralData} from "../src/periphery/BorrowerCallback.sol";

import {BaseTest} from "./BaseTest.sol";
import {ERC20} from "./helpers/ERC20.sol";

contract BorrowerCallbackTest is BaseTest {
    using UtilsLib for uint256;

    BorrowerCallback internal borrowerCallback;
    Obligation internal obligation;
    bytes32 internal id;
    Offer internal borrowerOffer;

    function setUp() public override {
        super.setUp();

        borrowerCallback = new BorrowerCallback(address(midnight));

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 100;
        obligation.collaterals.push(
            Collateral({
                token: address(collateralToken1),
                lltv: 0.75e18,
                maxLif: maxLif(0.75e18, 0.25e18),
                oracle: address(oracle1)
            })
        );
        obligation.collaterals.push(
            Collateral({
                token: address(collateralToken2),
                lltv: 0.75e18,
                maxLif: maxLif(0.75e18, 0.25e18),
                oracle: address(oracle2)
            })
        );
        obligation.collaterals = sortCollaterals(obligation.collaterals);
        obligation.rcfThreshold = 0;

        id = toId(obligation);

        borrowerOffer.buy = false;
        borrowerOffer.maker = borrower;
        borrowerOffer.receiverIfMakerIsSeller = borrower;
        borrowerOffer.maxUnits = type(uint256).max;
        borrowerOffer.obligation = obligation;
        borrowerOffer.expiry = block.timestamp + 200;
        borrowerOffer.tick = MAX_TICK;
    }

    function testConstructor() public view {
        assertEq(borrowerCallback.midnight(), address(midnight));
    }

    function testOnSellSingleCollateralMaker(uint256 units) public {
        units = bound(units, 1, 1e33);
        uint256 collateral = units.mulDivUp(WAD, obligation.collaterals[0].lltv);

        borrowerOffer.callback = address(borrowerCallback);
        CollateralData[] memory collateralData = new CollateralData[](1);
        collateralData[0] = CollateralData({collateralIndex: 0, amount: collateral});
        borrowerOffer.callbackData = abi.encode(collateralData);
        borrowerOffer.maxUnits = units;

        // Fund lender with loan tokens.
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), lender, units.mulDivUp(price, WAD));

        // Fund callback with collateral tokens and approve midnight.
        deal(obligation.collaterals[0].token, address(borrowerCallback), collateral);
        vm.prank(address(borrowerCallback));
        ERC20(obligation.collaterals[0].token).approve(address(midnight), collateral);

        // Authorize callback to supply collateral on behalf of borrower.
        authorize(borrower, address(borrowerCallback));

        assertEq(midnight.collateralOf(id, borrower, 0), 0);

        take(units, lender, borrowerOffer);

        assertEq(midnight.collateralOf(id, borrower, 0), collateral);
    }

    function testOnSellMultipleCollateralsMaker(uint256 units) public {
        units = bound(units, 1, 1e33);
        uint256 collateral0 = units.mulDivUp(WAD, obligation.collaterals[0].lltv);
        uint256 collateral1 = units.mulDivUp(WAD, obligation.collaterals[1].lltv);

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
        deal(obligation.collaterals[0].token, address(borrowerCallback), collateral0);
        deal(obligation.collaterals[1].token, address(borrowerCallback), collateral1);
        vm.prank(address(borrowerCallback));
        ERC20(obligation.collaterals[0].token).approve(address(midnight), collateral0);
        vm.prank(address(borrowerCallback));
        ERC20(obligation.collaterals[1].token).approve(address(midnight), collateral1);

        // Authorize callback to supply collateral on behalf of borrower.
        authorize(borrower, address(borrowerCallback));

        assertEq(midnight.collateralOf(id, borrower, 0), 0);
        assertEq(midnight.collateralOf(id, borrower, 1), 0);

        take(units, lender, borrowerOffer);

        assertEq(midnight.collateralOf(id, borrower, 0), collateral0);
        assertEq(midnight.collateralOf(id, borrower, 1), collateral1);
    }

    function testOnSellTaker(uint256 units) public {
        units = bound(units, 1, 1e33);
        uint256 collateral = units.mulDivUp(WAD, obligation.collaterals[0].lltv);

        // Lender makes a buy offer.
        Offer memory lenderOffer;
        lenderOffer.buy = true;
        lenderOffer.maker = lender;
        lenderOffer.maxUnits = units;
        lenderOffer.obligation = obligation;
        lenderOffer.expiry = block.timestamp + 200;
        lenderOffer.tick = MAX_TICK;

        // Fund lender with loan tokens.
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        deal(address(loanToken), lender, units.mulDivDown(price, WAD));

        // Fund callback with collateral tokens and approve midnight.
        deal(obligation.collaterals[0].token, address(borrowerCallback), collateral);
        vm.prank(address(borrowerCallback));
        ERC20(obligation.collaterals[0].token).approve(address(midnight), collateral);

        // Authorize callback to supply collateral on behalf of borrower.
        authorize(borrower, address(borrowerCallback));

        CollateralData[] memory collateralData = new CollateralData[](1);
        collateralData[0] = CollateralData({collateralIndex: 0, amount: collateral});

        assertEq(midnight.collateralOf(id, borrower, 0), 0);

        // Borrower takes the lender's buy offer, passing BorrowerCallback as taker callback.
        vm.prank(borrower);
        midnight.take(
            units,
            borrower,
            address(borrowerCallback),
            abi.encode(collateralData),
            borrower,
            lenderOffer,
            sig([lenderOffer]),
            root([lenderOffer]),
            proof([lenderOffer])
        );

        assertEq(midnight.collateralOf(id, borrower, 0), collateral);
    }

    function testOnSellUnauthorized() public {
        Obligation memory ob;
        vm.prank(makeAddr("attacker"));
        vm.expectRevert("unauthorized");
        borrowerCallback.onSell(ob, address(0), 0, 0, 0, "");
    }

    function testOnBuyReverts() public {
        Obligation memory ob;
        vm.expectRevert("not implemented");
        borrowerCallback.onBuy(ob, address(0), 0, 0, 0, "");
    }

    function testOnLiquidateReverts() public {
        Obligation memory ob;
        vm.expectRevert("not implemented");
        borrowerCallback.onLiquidate(ob, 0, 0, 0, address(0), "");
    }
}
