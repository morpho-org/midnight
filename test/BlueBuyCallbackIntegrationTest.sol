// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IMorpho, MarketParams} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {BlueBuyCallback} from "../src/periphery/blue-buy-callback/BlueBuyCallback.sol";
import {BlueBuyCallbackFactory} from "../src/periphery/blue-buy-callback/BlueBuyCallbackFactory.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";

contract BlueBuyCallbackIntegrationTest is BaseTest {
    using MarketParamsLib for MarketParams;
    using UtilsLib for uint256;

    uint256 internal constant BLUE_LLTV = 0.86e18;

    IMorpho internal blue;
    BlueBuyCallback internal callback;
    Market internal market;
    MarketParams internal blueMarketParams;
    uint256 internal observedBound;

    function setUp() public override {
        super.setUp();

        blue = IMorpho(deployCode("Morpho.sol", abi.encode(address(this))));
        blue.enableIrm(address(0));
        blue.enableLltv(BLUE_LLTV);

        blueMarketParams.loanToken = address(loanToken);
        blueMarketParams.collateralToken = address(collateralToken1);
        blueMarketParams.oracle = address(oracle1);
        blueMarketParams.irm = address(0);
        blueMarketParams.lltv = BLUE_LLTV;
        blue.createMarket(blueMarketParams);

        BlueBuyCallbackFactory factory = new BlueBuyCallbackFactory(address(midnight), address(blue));
        callback = BlueBuyCallback(factory.createBlueBuyCallback(lender, bytes32(0)));

        market.loanToken = address(loanToken);
        market.chainId = block.chainid;
        market.midnight = address(midnight);
        market.maturity = block.timestamp + 100;
        market.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: LLTV,
                    liquidationCursor: LIQUIDATION_CURSOR,
                    oracle: address(oracle1)
                })
            );

        bytes32 id = midnight.touchMarket(market);
        midnight.setMarketTickSpacing(id, 1);
    }

    function testBuyUsesLiquiditySuppliedOnBlue(uint256 units) public {
        units = bound(units, 1, 1e30);
        deal(address(loanToken), address(this), units);
        require(loanToken.approve(address(blue), units));
        (uint256 suppliedAssets, uint256 suppliedShares) =
            blue.supply(blueMarketParams, units, 0, address(callback), hex"");
        assertEq(suppliedAssets, units);
        assertGt(suppliedShares, 0);

        collateralize(market, borrower, units);

        Offer memory offer;
        offer.market = market;
        offer.buy = true;
        offer.maker = lender;
        offer.expiry = block.timestamp + 200;
        offer.tick = MAX_TICK;
        offer.callback = address(callback);
        offer.callbackData = abi.encode(blueMarketParams);
        offer.ratifier = address(dummyRatifier);
        offer.maxUnits = units.toUint128();
        offer.continuousFeeCap = type(uint256).max;

        (uint256 buyerAssets, uint256 sellerAssets) = take(units, borrower, offer);

        assertEq(buyerAssets, units);
        assertEq(loanToken.balanceOf(borrower), sellerAssets);
        assertEq(loanToken.balanceOf(address(callback)), 0);
        assertEq(blue.position(blueMarketParams.id(), address(callback)).supplyShares, 0);
        assertEq(midnight.credit(toId(market), lender), units);
        assertEq(midnight.debt(toId(market), borrower), units);
    }

    function testBuyerAssetsBoundIsCappedByAvailableLiquidity(uint256 suppliedAssets, uint256 borrowedAssets) public {
        suppliedAssets = bound(suppliedAssets, 2, 1e30);
        borrowedAssets = bound(borrowedAssets, 1, suppliedAssets / 2);
        deal(address(loanToken), address(this), suppliedAssets);
        require(loanToken.approve(address(blue), suppliedAssets));
        blue.supply(blueMarketParams, suppliedAssets, 0, address(callback), hex"");

        deal(address(collateralToken1), borrower, borrowedAssets * 2);
        vm.startPrank(borrower);
        require(collateralToken1.approve(address(blue), borrowedAssets * 2));
        blue.supplyCollateral(blueMarketParams, borrowedAssets * 2, borrower, hex"");
        blue.borrow(blueMarketParams, borrowedAssets, 0, borrower, borrower);
        vm.stopPrank();

        uint256 result = callback.buyerAssetsBound(bytes32(0), market, lender, abi.encode(blueMarketParams));

        assertEq(result, suppliedAssets - borrowedAssets);
    }

    function testBuyerAssetsBoundIsCappedByBlueBalance(uint256 suppliedAssets, uint256 flashloanedAssets) public {
        suppliedAssets = bound(suppliedAssets, 1, 1e30);
        flashloanedAssets = bound(flashloanedAssets, 1, suppliedAssets);
        deal(address(loanToken), address(this), suppliedAssets);
        require(loanToken.approve(address(blue), suppliedAssets));
        blue.supply(blueMarketParams, suppliedAssets, 0, address(callback), hex"");

        assertEq(callback.buyerAssetsBound(bytes32(0), market, lender, abi.encode(blueMarketParams)), suppliedAssets);

        blue.flashLoan(address(loanToken), flashloanedAssets, hex"");

        assertEq(observedBound, suppliedAssets - flashloanedAssets);
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata) external {
        observedBound = callback.buyerAssetsBound(bytes32(0), market, lender, abi.encode(blueMarketParams));
        require(loanToken.approve(address(blue), assets));
    }
}
