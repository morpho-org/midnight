// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {IMorpho, MarketParams} from "morpho-blue/src/interfaces/IMorpho.sol";
import {Market} from "../src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {BlueBuyCallback} from "../src/periphery/BlueBuyCallback.sol";
import {IBlueBuyCallback} from "../src/periphery/interfaces/IBlueBuyCallback.sol";
import {ERC20} from "./erc20s/ERC20.sol";

contract BlueBuyCallbackTest is Test {
    address internal owner = makeAddr("owner");
    ERC20 internal loanToken;
    ERC20 internal otherToken;
    MockMidnight internal midnight;
    IMorpho internal blue;
    BlueBuyCallback internal callback;
    Market internal market;
    MarketParams internal blueMarketParams;

    function setUp() public {
        loanToken = new ERC20("loan", "LOAN");
        otherToken = new ERC20("other", "OTHER");
        midnight = new MockMidnight();
        blue = IMorpho(deployCode("Morpho.sol", abi.encode(address(this))));
        callback = new BlueBuyCallback(owner, address(midnight), address(blue));

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

    function testOnBuyWithdrawsAndApproves(uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 0, 1e30);
        if (buyerAssets > 0) {
            deal(address(loanToken), address(this), buyerAssets);
            require(loanToken.approve(address(blue), buyerAssets));
            blue.supply(blueMarketParams, buyerAssets, 0, address(callback), hex"");
        }

        vm.prank(address(midnight));
        bytes32 result = callback.onBuy(bytes32(0), market, buyerAssets, 0, 0, owner, abi.encode(blueMarketParams));

        assertEq(result, CALLBACK_SUCCESS);
        assertEq(loanToken.balanceOf(address(callback)), buyerAssets);
        assertEq(loanToken.balanceOf(address(blue)), 0);
        assertEq(loanToken.allowance(address(callback), address(midnight)), type(uint256).max);
    }

    function testOnBuyWithdrawsAndApprovesZeroAssets() public {
        testOnBuyWithdrawsAndApproves(0);
    }

    function testOnBuyRevertsIfCallerIsNotMidnight(address caller) public {
        vm.assume(caller != address(midnight));
        vm.expectRevert(IBlueBuyCallback.NotMidnight.selector);
        vm.prank(caller);
        callback.onBuy(bytes32(0), market, 0, 0, 0, owner, abi.encode(blueMarketParams));
    }

    function testOnBuyRevertsIfBuyerIsNotOwner(address buyer) public {
        vm.assume(buyer != owner);
        vm.expectRevert(IBlueBuyCallback.NotOwnerBuyer.selector);
        vm.prank(address(midnight));
        callback.onBuy(bytes32(0), market, 0, 0, 0, buyer, abi.encode(blueMarketParams));
    }

    function testOnBuyRevertsIfLoanTokenIsInconsistent() public {
        blueMarketParams.loanToken = address(otherToken);

        vm.expectRevert(IBlueBuyCallback.InconsistentLoanToken.selector);
        vm.prank(address(midnight));
        callback.onBuy(bytes32(0), market, 0, 0, 0, owner, abi.encode(blueMarketParams));
    }
}

contract MockMidnight {}
