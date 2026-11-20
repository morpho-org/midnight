// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {IMorpho, MarketParams} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {Market} from "../src/interfaces/IMidnight.sol";
import {BlueSwapBuyCallback} from "../src/periphery/blue-swap-buy-callback/BlueSwapBuyCallback.sol";
import {IBlueSwapBuyCallback} from "../src/periphery/blue-swap-buy-callback/interfaces/IBlueSwapBuyCallback.sol";
import {ERC20} from "./erc20s/ERC20.sol";

contract BlueSwapBuyCallbackAuthorizationTest is Test {
    address internal owner = makeAddr("owner");
    ERC20 internal loanToken;
    ERC20 internal otherToken;
    SwapMockMidnight internal midnight;
    IMorpho internal blue;
    BlueSwapBuyCallback internal callback;
    Market internal market;
    MarketParams internal blueMarketParams;

    function setUp() public {
        loanToken = new ERC20("loan", "LOAN");
        otherToken = new ERC20("other", "OTHER");
        midnight = new SwapMockMidnight();
        blue = IMorpho(deployCode("Morpho.sol", abi.encode(address(this))));
        callback = new BlueSwapBuyCallback(owner, address(midnight), address(blue));

        market.midnight = address(midnight);
        market.loanToken = address(loanToken);
        blueMarketParams.loanToken = address(loanToken);
        blueMarketParams.collateralToken = makeAddr("collateralToken");
        blueMarketParams.oracle = makeAddr("oracle");
        blueMarketParams.irm = address(0);
        blueMarketParams.lltv = 0.86e18;

        blue.enableIrm(blueMarketParams.irm);
        blue.enableLltv(blueMarketParams.lltv);
        blue.createMarket(blueMarketParams);
    }

    function testConstructorAuthorizesOwnerOnBlue() public view {
        assertTrue(blue.isAuthorized(address(callback), owner));
    }

    function testSetAuthorization() public {
        address authorized = makeAddr("authorized");

        vm.prank(owner);
        callback.setAuthorization(authorized, true);

        assertTrue(blue.isAuthorized(address(callback), authorized));
    }

    function testSetAuthorizationCanRevoke() public {
        address authorized = makeAddr("authorized");
        vm.startPrank(owner);
        callback.setAuthorization(authorized, true);
        callback.setAuthorization(authorized, false);
        vm.stopPrank();

        assertFalse(blue.isAuthorized(address(callback), authorized));
    }

    function testSetAuthorizationAllowsNoOp() public {
        address authorized = makeAddr("authorized");

        vm.prank(owner);
        callback.setAuthorization(authorized, false);

        assertFalse(blue.isAuthorized(address(callback), authorized));
    }

    function testSetAuthorizationRevertsIfCallerIsNotOwner() public {
        vm.expectRevert(IBlueSwapBuyCallback.NotOwner.selector);
        callback.setAuthorization(makeAddr("authorized"), true);
    }

    function testSkim(address caller, uint256 assets) public {
        assets = bound(assets, 0, 1e30);
        deal(address(otherToken), address(callback), assets);

        vm.expectEmit(address(callback));
        emit IBlueSwapBuyCallback.Skim(caller, address(otherToken), assets);
        vm.prank(caller);
        callback.skim(address(otherToken));

        assertEq(otherToken.balanceOf(address(callback)), 0);
        assertEq(otherToken.balanceOf(owner), assets);
    }
}

contract SwapMockMidnight {}
