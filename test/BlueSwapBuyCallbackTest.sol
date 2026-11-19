// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IMorpho, MarketParams} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
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

abstract contract BlueSwapBuyCallbackBase is BaseTest {
    using MarketParamsLib for MarketParams;

    IMorpho internal blue;
    BlueSwapBuyCallback internal callback;
    MakerCallbackDataRatifier internal wrapper;
    TestSwapper internal swapper;
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
        return abi.encode(abi.encode(params, price), abi.encode(address(swapper), hex""));
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

    function testFullTake() public {
        supply(1e6);
        configure(1e18);
        collateralize(market, borrower, 1e18);
        (Offer memory offer, bytes memory proof) = signedOffer(1e18);
        vm.prank(borrower);
        (uint256 buyerAssets, uint256 sellerAssets) =
            midnight.take(offer, proof, 1e18, borrower, borrower, address(0), hex"");
        assertEq(buyerAssets, 1e18);
        assertEq(tokenOut.balanceOf(borrower), sellerAssets);
        assertEq(blue.position(params.id(), address(callback)).supplyShares, 0);
        assertEq(tokenIn.balanceOf(address(swapper)), 1e6);
        assertEq(midnight.credit(toId(market), lender), 1e18);
    }

    function testSurplusAndSkim() public {
        supply(1e6);
        configure(2e18);
        buy(1e18);
        vm.prank(address(midnight));
        require(tokenOut.transferFrom(address(callback), borrower, 1e18));
        assertEq(tokenOut.balanceOf(address(callback)), 1e18);
        callback.skim(address(tokenOut));
        assertEq(tokenOut.balanceOf(lender), 1e18);
        assertEq(tokenOut.balanceOf(address(callback)), 0);
    }

    function testShortDeliveryAndPreexistingBalance() public {
        supply(1e6);
        configure(1e18 - 1);
        deal(address(tokenOut), address(callback), 10e18);
        vm.expectRevert(IBlueSwapBuyCallback.InsufficientDelivery.selector);
        vm.prank(address(midnight));
        callback.onBuy(bytes32(0), market, 1e18, 0, 0, lender, data());
        assertEq(tokenOut.balanceOf(address(callback)), 10e18);
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
        buy(0);
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
        configure(1e6);
        buy(1e6);
        assertEq(tokenIn.balanceOf(address(swapper)), 1e18);
        assertEq(tokenOut.balanceOf(address(callback)), 1e6);
    }

    function testBound() public {
        assertEq(callback.buyerAssetsBound(bytes32(0), market, lender, data()), 0);
        supply(1e6);
        assertEq(callback.buyerAssetsBound(bytes32(0), market, lender, data()), 1e18);
        deal(address(tokenIn), address(blue), 5e5);
        assertEq(callback.buyerAssetsBound(bytes32(0), market, lender, data()), 5e17);
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

    function testRoundingAndSwapEvent() public {
        supply(1e6);
        configure(1e18 + 1);
        vm.expectEmit(address(callback));
        emit IBlueSwapBuyCallback.Swap(address(midnight), bytes32(0), address(swapper), 1e6, 1e18 + 1);
        buy(1e18 + 1);
        assertEq(tokenIn.balanceOf(address(swapper)), 1e6);
    }

    function testPositiveBuyWithZeroBlueAssets() public {
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

    function testReentrantTake() public {
        supply(2e6);
        configure(1e18);
        collateralize(market, address(swapper), 1e18);
        collateralize(market, borrower, 1e18);
        (Offer memory offer, bytes memory proof) = signedOffer(2e18);
        swapper.configure(
            1e18,
            CALLBACK_SUCCESS,
            address(midnight),
            abi.encodeCall(midnight.take, (offer, proof, 1e18, address(swapper), address(swapper), address(0), hex""))
        );
        vm.prank(borrower);
        midnight.take(offer, proof, 1e18, borrower, borrower, address(0), hex"");
        assertEq(swapper.attackError(), abi.encodeWithSelector(IBlueSwapBuyCallback.Reentrancy.selector));
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
