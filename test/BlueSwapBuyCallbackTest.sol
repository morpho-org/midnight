// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IMorpho, MarketParams} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {ORACLE_PRICE_SCALE} from "../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {BlueSwapBuyCallback} from "../src/periphery/blue-swap-buy-callback/BlueSwapBuyCallback.sol";
import {IBlueSwapBuyCallback} from "../src/periphery/blue-swap-buy-callback/interfaces/IBlueSwapBuyCallback.sol";
import {ISwapper} from "../src/periphery/blue-swap-buy-callback/interfaces/ISwapper.sol";
import {ERC20Lib} from "../src/periphery/libraries/ERC20Lib.sol";
import {MakerCallbackDataRatifier} from "../src/ratifiers/MakerCallbackDataRatifier.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";
import {Signature, IEcrecoverRatifier} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {BaseTest, LLTV, LIQUIDATION_CURSOR} from "./BaseTest.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {GenericSwapper} from "./helpers/GenericSwapper.sol";
import {MockExchange} from "./helpers/MockExchange.sol";

contract SwapToken is ERC20 {
    uint8 public decimals;

    constructor(uint8 _decimals) ERC20("swap", "SWAP") {
        decimals = _decimals;
    }
}

contract TestSwapper is ISwapper {
    uint256 public delivery;
    uint256 public calls;
    bytes32 public result = CALLBACK_SUCCESS;
    address public target;
    bytes public attack;
    bytes public attackError;

    function configure(uint256 _delivery, bytes32 _result, address _target, bytes memory _attack) external {
        delivery = _delivery;
        result = _result;
        target = _target;
        attack = _attack;
    }

    function onSwap(address, address tokenOut, uint256, uint256, bytes memory) external returns (bytes32) {
        calls++;
        if (target != address(0)) {
            (bool success, bytes memory reason) = target.call(attack);
            require(!success, "attack succeeded");
            attackError = reason;
        }
        require(ERC20(tokenOut).transfer(msg.sender, delivery));
        return result;
    }
}

contract NestedTakeSwapper is ISwapper {
    address public midnight;
    bytes public nestedTake;

    function configure(address _midnight, bytes memory _nestedTake) external {
        midnight = _midnight;
        nestedTake = _nestedTake;
    }

    function onSwap(address, address tokenOut, uint256, uint256 minAmountOut, bytes memory) external returns (bytes32) {
        if (nestedTake.length > 0) {
            bytes memory callData = nestedTake;
            delete nestedTake;
            (bool success, bytes memory reason) = midnight.call(callData);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(reason, 0x20), mload(reason))
                }
            }
        }
        require(ERC20(tokenOut).transfer(msg.sender, minAmountOut));
        return CALLBACK_SUCCESS;
    }
}

abstract contract BlueSwapBuyCallbackBase is BaseTest {
    using MarketParamsLib for MarketParams;

    IMorpho internal blue;
    BlueSwapBuyCallback internal callback;
    MakerCallbackDataRatifier internal wrapper;
    TestSwapper internal swapper;
    GenericSwapper internal genericSwapper;
    MockExchange internal exchange;
    bytes internal swapData;
    SwapToken internal tokenIn;
    SwapToken internal tokenOut;
    Market internal market;
    MarketParams internal params;
    uint256 internal price = 1e48;

    function setUp() public override {
        super.setUp();
        blue = IMorpho(deployCode("Morpho.sol", abi.encode(address(this))));
        blue.enableIrm(address(0));
        blue.enableLltv(0.86e18);
        tokenIn = new SwapToken(6);
        tokenOut = new SwapToken(18);
        params = MarketParams(address(tokenIn), address(collateralToken1), address(oracle1), address(0), 0.86e18);
        blue.createMarket(params);
        callback = new BlueSwapBuyCallback(lender, address(midnight), address(blue));
        wrapper = new MakerCallbackDataRatifier(address(ecrecoverRatifier));
        vm.prank(lender);
        midnight.setIsAuthorized(address(wrapper), true, lender);
        swapper = new TestSwapper();
        market.loanToken = address(tokenOut);
        market.chainId = block.chainid;
        market.midnight = address(midnight);
        market.maturity = block.timestamp + 100;
        market.collateralParams
            .push(CollateralParams(address(collateralToken1), LLTV, LIQUIDATION_CURSOR, address(oracle1)));
        midnight.setMarketTickSpacing(midnight.touchMarket(market), 1);
    }

    function data() internal view returns (bytes memory) {
        if (address(genericSwapper) != address(0)) {
            return abi.encode(abi.encode(params, price), abi.encode(address(genericSwapper), swapData));
        }
        return abi.encode(abi.encode(params, price), abi.encode(address(swapper), hex""));
    }

    function configureRoute(uint256 amountIn, uint256 output) internal {
        genericSwapper = new GenericSwapper();
        exchange = new MockExchange();
        exchange.setRate(price);
        deal(address(tokenOut), address(exchange), output);
        swapData = abi.encode(
            address(exchange),
            abi.encodeCall(exchange.swap, (address(tokenIn), address(tokenOut), amountIn)),
            otherLender
        );
    }

    function assertRouteCleared() internal view {
        assertEq(tokenIn.balanceOf(address(genericSwapper)), 0);
        assertEq(tokenOut.balanceOf(address(genericSwapper)), 0);
        assertEq(tokenIn.allowance(address(genericSwapper), address(exchange)), 0);
    }

    function supply(uint256 assets) internal {
        deal(address(tokenIn), address(this), assets);
        ERC20Lib.safeApprove(address(tokenIn), address(blue), assets);
        blue.supply(params, assets, 0, address(callback), hex"");
    }

    function configure(uint256 delivery) internal {
        deal(address(tokenOut), address(swapper), delivery);
        swapper.configure(delivery, CALLBACK_SUCCESS, address(0), hex"");
    }

    function buy(uint256 assets) internal {
        vm.prank(address(midnight));
        assertEq(callback.onBuy(bytes32(0), market, assets, 0, 0, lender, data()), CALLBACK_SUCCESS);
    }

    function signedOffer(uint128 units) internal view returns (Offer memory offer, bytes memory ratifierData) {
        offer.market = market;
        offer.buy = true;
        offer.maker = lender;
        offer.expiry = block.timestamp + 200;
        offer.tick = MAX_TICK;
        offer.callback = address(callback);
        offer.callbackData = abi.encode(params, price);
        offer.ratifier = address(wrapper);
        offer.maxUnits = units;
        offer.continuousFeeCap = type(uint256).max;
        bytes32 root = HashLib.hashOffer(offer);
        Signature memory sig = signature(root, privateKey[lender], address(ecrecoverRatifier), 0);
        ratifierData = abi.encode(sig, root, 0, new bytes32[](0));
        offer.callbackData = data();
    }
}

contract BlueSwapBuyCallbackTest is BlueSwapBuyCallbackBase {
    using MarketParamsLib for MarketParams;

    function testSameTokenWithZeroSwapper() public {
        market.loanToken = address(tokenIn);
        supply(1e6);
        bytes memory callbackData = abi.encode(abi.encode(params, ORACLE_PRICE_SCALE), abi.encode(address(0), hex""));
        assertEq(callback.buyerAssetsBound(bytes32(0), market, lender, callbackData), 1e6);
        vm.expectEmit(address(callback));
        emit IBlueSwapBuyCallback.OnBuy(address(midnight), bytes32(0), 1e6, 1e6, address(0));
        vm.prank(address(midnight));
        assertEq(callback.onBuy(bytes32(0), market, 1e6, 0, 0, lender, callbackData), CALLBACK_SUCCESS);
        assertEq(tokenIn.balanceOf(address(callback)), 1e6);
        assertEq(tokenIn.allowance(address(callback), address(midnight)), 1e6);
        assertEq(blue.position(params.id(), address(callback)).supplyShares, 0);
        assertEq(swapper.calls(), 0);
    }

    function testSingleRootThreeMarketsRlusd6Decimals() public {
        singleRootThreeMarkets(6);
    }

    function testSingleRootThreeMarketsRlusd18Decimals() public {
        singleRootThreeMarkets(18);
    }

    function singleRootThreeMarkets(uint8 rlusdDecimals) internal {
        SwapToken usdt = new SwapToken(6);
        SwapToken rlusd = new SwapToken(rlusdDecimals);
        SwapToken[3] memory tokens = [tokenIn, usdt, rlusd];
        uint128[3] memory units = [uint128(1e6), uint128(1e6), uint128(10 ** rlusdDecimals)];
        uint256[3] memory prices = [ORACLE_PRICE_SCALE, ORACLE_PRICE_SCALE, 10 ** (uint256(rlusdDecimals) + 30)];
        Offer[3] memory offers;
        bytes32[4] memory leaves;
        supply(3e6);
        uint256 initialShares = blue.position(params.id(), address(callback)).supplyShares;

        for (uint256 i; i < 3; i++) {
            Offer memory offer;
            offer.market = abi.decode(abi.encode(market), (Market));
            offer.market.loanToken = address(tokens[i]);
            midnight.setMarketTickSpacing(midnight.touchMarket(offer.market), 1);
            collateralize(offer.market, borrower, units[i]);
            offer.buy = true;
            offer.maker = lender;
            offer.expiry = block.timestamp + 200;
            offer.tick = MAX_TICK;
            offer.callback = address(callback);
            offer.callbackData = abi.encode(params, prices[i]);
            offer.ratifier = address(wrapper);
            offer.group = bytes32(i);
            offer.maxUnits = units[i];
            offer.continuousFeeCap = type(uint256).max;
            leaves[i] = HashLib.hashOffer(offer);
            offers[i] = offer;
        }

        bytes32 left = keccak256(abi.encode(leaves[0], leaves[1]));
        bytes32 right = keccak256(abi.encode(leaves[2], leaves[3]));
        bytes32 root = keccak256(abi.encode(left, right));
        Signature memory sig = signature(root, privateKey[lender], address(ecrecoverRatifier), 2);
        GenericSwapper routeSwapper = new GenericSwapper();
        MockExchange dex = new MockExchange();
        for (uint256 i; i < 3; i++) {
            bytes memory makerData = offers[i].callbackData;
            bytes memory takerData = abi.encode(address(0), hex"");
            if (i > 0) {
                dex.setRate(prices[i]);
                deal(address(tokens[i]), address(dex), units[i]);
                bytes memory route = abi.encode(
                    address(dex), abi.encodeCall(dex.swap, (address(tokenIn), address(tokens[i]), 1e6)), otherLender
                );
                takerData = abi.encode(address(routeSwapper), route);
            }
            offers[i].callbackData = abi.encode(makerData, takerData);
            bytes32[] memory proof = new bytes32[](2);
            proof[0] = leaves[i ^ 1];
            proof[1] = i < 2 ? right : left;
            vm.prank(borrower);
            (uint256 buyerAssets, uint256 sellerAssets) = midnight.take(
                offers[i], abi.encode(sig, root, i, proof), units[i], borrower, borrower, address(0), hex""
            );
            assertEq(buyerAssets, units[i]);
            assertEq(tokens[i].balanceOf(borrower), sellerAssets);
            assertEq(tokens[i].balanceOf(address(callback)), 0);
            assertEq(tokens[i].balanceOf(address(routeSwapper)), 0);
            assertEq(midnight.credit(toId(offers[i].market), lender), units[i]);
            assertEq(midnight.debt(toId(offers[i].market), borrower), units[i]);
            assertEq(blue.position(params.id(), address(callback)).supplyShares, initialShares * (2 - i) / 3);
            assertEq(tokenIn.balanceOf(address(blue)), (2 - i) * 1e6);
            assertEq(tokenIn.balanceOf(address(dex)), i * 1e6);
            assertEq(tokenIn.allowance(address(routeSwapper), address(dex)), 0);
        }
    }

    function testFullTake() public {
        supply(1e6);
        configureRoute(1e6, 1e18);
        collateralize(market, borrower, 1e18);
        (Offer memory offer, bytes memory proof) = signedOffer(1e18);
        vm.prank(borrower);
        (uint256 buyerAssets, uint256 sellerAssets) =
            midnight.take(offer, proof, 1e18, borrower, borrower, address(0), hex"");
        assertEq(buyerAssets, 1e18);
        assertEq(tokenOut.balanceOf(borrower), sellerAssets);
        assertEq(blue.position(params.id(), address(callback)).supplyShares, 0);
        assertEq(tokenIn.balanceOf(address(exchange)), 1e6);
        assertRouteCleared();
        assertEq(midnight.credit(toId(market), lender), 1e18);
    }

    function testSkimDonations() public {
        deal(address(tokenOut), address(callback), 1e18);
        assertEq(tokenOut.balanceOf(address(callback)), 1e18);
        callback.skim(address(tokenOut));
        assertEq(tokenOut.balanceOf(lender), 1e18);
        assertEq(tokenOut.balanceOf(address(callback)), 0);
    }

    function testShortDeliveryRevertsThroughMidnight() public {
        supply(1e6);
        configure(1e18 - 1);
        collateralize(market, borrower, 1e18);
        (Offer memory offer, bytes memory proof) = signedOffer(1e18);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Insufficient balance"));
        vm.prank(borrower);
        midnight.take(offer, proof, 1e18, borrower, borrower, address(0), hex"");
        assertEq(tokenIn.balanceOf(address(blue)), 1e6);
    }

    function testCrossTokenZeroSwapperRevertsThroughMidnight() public {
        supply(1e6);
        collateralize(market, borrower, 1e18);
        (Offer memory offer, bytes memory proof) = signedOffer(1e18);
        offer.callbackData = abi.encode(abi.encode(params, price), abi.encode(address(0), hex""));
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Insufficient balance"));
        vm.prank(borrower);
        midnight.take(offer, proof, 1e18, borrower, borrower, address(0), hex"");
        assertEq(tokenIn.balanceOf(address(blue)), 1e6);
        assertEq(tokenIn.balanceOf(address(callback)), 0);
    }

    function testPreexistingBalanceCanFundDelivery() public {
        supply(1e6);
        configure(1e18 - 1);
        deal(address(tokenOut), address(callback), 1);
        collateralize(market, borrower, 1e18);
        (Offer memory offer, bytes memory proof) = signedOffer(1e18);
        vm.prank(borrower);
        (uint256 buyerAssets, uint256 sellerAssets) =
            midnight.take(offer, proof, 1e18, borrower, borrower, address(0), hex"");
        assertEq(buyerAssets, 1e18);
        assertEq(tokenOut.balanceOf(borrower), sellerAssets);
        assertEq(tokenOut.balanceOf(address(callback)), 0);
    }

    function testInvalidReturn() public {
        supply(1e6);
        configure(1e18);
        swapper.configure(1e18, bytes32(0), address(0), hex"");
        vm.expectRevert(IBlueSwapBuyCallback.InvalidSwapCallback.selector);
        vm.prank(address(midnight));
        callback.onBuy(bytes32(0), market, 1e18, 0, 0, lender, data());
    }

    function testZeroBuy() public {
        price = 0;
        vm.expectEmit(address(callback));
        emit IBlueSwapBuyCallback.OnBuy(address(midnight), bytes32(0), 0, 0, address(0));
        vm.prank(address(midnight));
        assertEq(
            callback.onBuy(bytes32(0), market, 0, 0, 0, lender, abi.encode(abi.encode(params, price), hex"")),
            CALLBACK_SUCCESS
        );
        assertEq(swapper.calls(), 0);
        assertEq(tokenOut.allowance(address(callback), address(midnight)), 0);
    }

    function testZeroPrice() public {
        price = 0;
        vm.expectRevert();
        vm.prank(address(midnight));
        callback.onBuy(bytes32(0), market, 1, 0, 0, lender, data());
    }

    function testReverseDecimals() public {
        tokenIn = new SwapToken(18);
        tokenOut = new SwapToken(6);
        params.loanToken = address(tokenIn);
        blue.createMarket(params);
        market.loanToken = address(tokenOut);
        price = 1e24;
        supply(1e18);
        assertEq(callback.buyerAssetsBound(bytes32(0), market, lender, data()), 1e6);
        configureRoute(1e18, 1e6);
        buy(1e6);
        assertEq(tokenIn.balanceOf(address(exchange)), 1e18);
        assertEq(tokenOut.balanceOf(address(callback)), 1e6);
        assertRouteCleared();
    }

    function testRouteSurplus() public {
        supply(1e6);
        configureRoute(1e6, 2e18);
        exchange.setRate(2 * price);
        buy(1e18);
        assertEq(tokenOut.balanceOf(address(callback)), 1e18);
        assertEq(tokenOut.balanceOf(otherLender), 1e18);
        assertRouteCleared();
    }

    function testRouteShortDelivery() public {
        supply(1e6);
        configureRoute(1e6, 1e18);
        exchange.setRate(price / 2);
        collateralize(market, borrower, 1e18);
        (Offer memory offer, bytes memory proof) = signedOffer(1e18);
        vm.expectRevert(GenericSwapper.InsufficientOutput.selector);
        vm.prank(borrower);
        midnight.take(offer, proof, 1e18, borrower, borrower, address(0), hex"");
        assertEq(tokenIn.balanceOf(address(blue)), 1e6);
        assertRouteCleared();
    }

    function testRouteBubblesRevert() public {
        supply(1e6);
        configureRoute(1e6, 0);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "Insufficient balance"));
        vm.prank(address(midnight));
        callback.onBuy(bytes32(0), market, 1e18, 0, 0, lender, data());
        assertEq(tokenIn.balanceOf(address(blue)), 1e6);
        assertRouteCleared();
    }

    function testRouteZeroAmounts() public {
        configureRoute(0, 0);
        assertEq(genericSwapper.onSwap(address(tokenIn), address(tokenOut), 0, 0, swapData), CALLBACK_SUCCESS);
        assertRouteCleared();
    }

    function testRouteRefundsUnusedInput() public {
        configureRoute(5e5, 5e17);
        deal(address(tokenIn), address(genericSwapper), 1e6);
        assertEq(genericSwapper.onSwap(address(tokenIn), address(tokenOut), 1e6, 5e17, swapData), CALLBACK_SUCCESS);
        assertEq(tokenIn.balanceOf(otherLender), 5e5);
        assertEq(tokenOut.balanceOf(address(this)), 5e17);
        assertRouteCleared();
    }

    function testRouteMalformedData() public {
        configureRoute(0, 0);
        vm.expectRevert();
        genericSwapper.onSwap(address(tokenIn), address(tokenOut), 0, 0, hex"");
        assertRouteCleared();
    }

    function testBound() public {
        assertEq(callback.buyerAssetsBound(bytes32(0), market, lender, data()), 0);
        supply(1e6);
        assertEq(callback.buyerAssetsBound(bytes32(0), market, lender, data()), 1e18);
        deal(address(tokenIn), address(blue), 5e5);
        assertEq(callback.buyerAssetsBound(bytes32(0), market, lender, data()), 5e17);
        price = 0;
        assertEq(callback.buyerAssetsBound(bytes32(0), market, lender, data()), 0);
    }

    function testBoundLiquidity() public {
        supply(1e6);
        deal(address(collateralToken1), borrower, 1e18);
        vm.startPrank(borrower);
        ERC20Lib.safeApprove(address(collateralToken1), address(blue), 1e18);
        blue.supplyCollateral(params, 1e18, borrower, hex"");
        blue.borrow(params, 4e5, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(callback.buyerAssetsBound(bytes32(0), market, lender, data()), 6e17);
    }

    function testConvertedBoundIsTakeable() public {
        supply(1e6);
        uint128 units = uint128(callback.buyerAssetsBound(bytes32(0), market, lender, data()));
        assertEq(units, 1e18);
        configureRoute(1e6, units);
        collateralize(market, borrower, units);
        (Offer memory offer, bytes memory proof) = signedOffer(units);
        vm.prank(borrower);
        (uint256 buyerAssets,) = midnight.take(offer, proof, units, borrower, borrower, address(0), hex"");
        assertEq(buyerAssets, units);
        assertEq(blue.position(params.id(), address(callback)).supplyShares, 0);
        assertRouteCleared();
    }

    function testRoundingAndOnBuyEvent() public {
        supply(1e6);
        configure(1e18 + 1);
        vm.expectEmit(address(callback));
        emit IBlueSwapBuyCallback.OnBuy(address(midnight), bytes32(0), 1e18 + 1, 1e6, address(swapper));
        buy(1e18 + 1);
        assertEq(tokenIn.balanceOf(address(swapper)), 1e6);
    }

    function testPositiveBuyWithZeroSourceAssets() public {
        configure(1);
        buy(1);
        assertEq(swapper.calls(), 1);
        assertEq(tokenOut.balanceOf(address(callback)), 1);
        assertEq(tokenIn.balanceOf(address(swapper)), 0);
    }

    function testCallerAndBuyerChecks() public {
        vm.expectRevert(IBlueSwapBuyCallback.NotMidnight.selector);
        callback.onBuy(bytes32(0), market, 0, 0, 0, lender, data());
        vm.expectRevert(IBlueSwapBuyCallback.NotOwnerBuyer.selector);
        vm.prank(address(midnight));
        callback.onBuy(bytes32(0), market, 0, 0, 0, borrower, data());
    }

    function testSwapperCannotWithdrawOrBorrow() public {
        supply(2e6);
        configure(1e18);
        swapper.configure(
            1e18,
            CALLBACK_SUCCESS,
            address(blue),
            abi.encodeCall(blue.withdraw, (params, 1, 0, address(callback), address(swapper)))
        );
        buy(1e18);
        assertEq(swapper.attackError(), abi.encodeWithSignature("Error(string)", "unauthorized"));
        configure(1e18);
        swapper.configure(
            1e18,
            CALLBACK_SUCCESS,
            address(blue),
            abi.encodeCall(blue.borrow, (params, 1, 0, address(callback), address(swapper)))
        );
        buy(1e18);
        assertEq(swapper.attackError(), abi.encodeWithSignature("Error(string)", "unauthorized"));
        assertFalse(blue.isAuthorized(address(callback), address(swapper)));
    }

    function testSwapperCannotCallOnBuy() public {
        supply(1e6);
        configure(1e18);
        swapper.configure(
            1e18,
            CALLBACK_SUCCESS,
            address(callback),
            abi.encodeCall(callback.onBuy, (bytes32(0), market, 0, 0, 0, lender, data()))
        );
        buy(1e18);
        assertEq(swapper.attackError(), abi.encodeWithSelector(IBlueSwapBuyCallback.NotMidnight.selector));
    }

    function testNestedTakeSettlesBothFills() public {
        supply(2e6);
        NestedTakeSwapper nestedSwapper = new NestedTakeSwapper();
        deal(address(tokenOut), address(nestedSwapper), 2e18);
        collateralize(market, address(nestedSwapper), 1e18);
        collateralize(market, borrower, 1e18);
        (Offer memory offer, bytes memory proof) = signedOffer(2e18);
        offer.callbackData = abi.encode(abi.encode(params, price), abi.encode(address(nestedSwapper), hex""));
        nestedSwapper.configure(
            address(midnight),
            abi.encodeCall(
                midnight.take, (offer, proof, 1e18, address(nestedSwapper), address(nestedSwapper), address(0), hex"")
            )
        );
        vm.prank(borrower);
        (uint256 buyerAssets, uint256 sellerAssets) =
            midnight.take(offer, proof, 1e18, borrower, borrower, address(0), hex"");
        assertEq(buyerAssets, 1e18);
        assertEq(tokenOut.balanceOf(borrower), sellerAssets);
        assertEq(tokenOut.balanceOf(address(nestedSwapper)), sellerAssets);
        assertEq(midnight.credit(toId(market), lender), 2e18);
        assertEq(midnight.debt(toId(market), borrower), 1e18);
        assertEq(midnight.debt(toId(market), address(nestedSwapper)), 1e18);
        assertEq(tokenIn.balanceOf(address(nestedSwapper)), 2e6);
        assertEq(blue.position(params.id(), address(callback)).supplyShares, 0);
        assertEq(tokenOut.balanceOf(address(callback)), 0);
        assertEq(tokenOut.allowance(address(callback), address(midnight)), 0);
    }
}

contract MakerCallbackDataRatifierTest is BlueSwapBuyCallbackBase {
    function testTakerDataCanChange() public view {
        (Offer memory offer, bytes memory proof) = signedOffer(1e18);
        offer.callbackData = abi.encode(abi.encode(params, price), abi.encode(address(123), hex"1234"));
        assertEq(wrapper.isRatified(offer, proof, borrower), CALLBACK_SUCCESS);
        (bytes memory makerData,) = abi.decode(offer.callbackData, (bytes, bytes));
        assertEq(makerData, abi.encode(params, price));
    }

    function testMakerDataCannotChange() public {
        (Offer memory offer, bytes memory proof) = signedOffer(1e18);
        offer.callbackData = abi.encode(abi.encode(params, price / 2), abi.encode(address(swapper), hex""));
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        wrapper.isRatified(offer, proof, borrower);
        params.loanToken = address(tokenOut);
        offer.callbackData = data();
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        wrapper.isRatified(offer, proof, borrower);
    }

    function testMalformedData() public {
        (Offer memory offer, bytes memory proof) = signedOffer(1e18);
        offer.callbackData = hex"";
        vm.expectRevert();
        wrapper.isRatified(offer, proof, borrower);
    }

    function testDirectRatifierLeafNotInterchangeable() public {
        (Offer memory offer, bytes memory proof) = signedOffer(1e18);
        offer.ratifier = address(ecrecoverRatifier);
        vm.expectRevert(IEcrecoverRatifier.InvalidProof.selector);
        wrapper.isRatified(offer, proof, borrower);
    }
}
