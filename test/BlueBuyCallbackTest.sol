// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Market} from "../src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../src/libraries/ConstantsLib.sol";
import {BlueBuyCallback} from "../src/periphery/BlueBuyCallback.sol";
import {BlueMarketParams, IBlue} from "../src/periphery/interfaces/IBlue.sol";
import {IBlueBuyCallback} from "../src/periphery/interfaces/IBlueBuyCallback.sol";
import {ERC20} from "./erc20s/ERC20.sol";

contract BlueBuyCallbackTest is Test {
    address internal owner = makeAddr("owner");
    ERC20 internal loanToken;
    ERC20 internal otherToken;
    MockMidnight internal midnight;
    MockBlue internal blue;
    BlueBuyCallback internal callback;
    Market internal market;
    BlueMarketParams internal blueMarketParams;

    function setUp() public {
        loanToken = new ERC20("loan", "LOAN");
        otherToken = new ERC20("other", "OTHER");
        midnight = new MockMidnight();
        blue = new MockBlue();
        callback = new BlueBuyCallback(owner, address(midnight), address(blue));

        market.midnight = address(midnight);
        market.loanToken = address(loanToken);
        blueMarketParams.loanToken = address(loanToken);
        blueMarketParams.collateralToken = makeAddr("collateralToken");
        blueMarketParams.oracle = makeAddr("oracle");
        blueMarketParams.irm = makeAddr("irm");
        blueMarketParams.lltv = 0.86e18;
    }

    function testConstructorAuthorizesOwnerOnBlue() public view {
        assertTrue(blue.isAuthorized(address(callback), owner));
    }

    function testOnBuyWithdrawsAndApproves(uint256 buyerAssets) public {
        buyerAssets = bound(buyerAssets, 0, type(uint128).max);
        deal(address(loanToken), address(blue), buyerAssets);

        vm.prank(address(midnight));
        bytes32 result = callback.onBuy(bytes32(0), market, buyerAssets, 0, 0, owner, abi.encode(blueMarketParams));

        assertEq(result, CALLBACK_SUCCESS);
        assertEq(blue.recordedOnBehalf(), address(callback));
        assertEq(blue.recordedReceiver(), address(callback));
        assertEq(blue.recordedAssets(), buyerAssets);
        assertEq(blue.recordedShares(), 0);
        assertEq(blue.recordedLoanToken(), address(loanToken));
        assertEq(loanToken.balanceOf(address(callback)), buyerAssets);
        assertEq(loanToken.allowance(address(callback), address(midnight)), buyerAssets);
    }

    function testOnBuyRevertsIfCallerIsNotMidnight() public {
        vm.expectRevert(IBlueBuyCallback.NotMidnight.selector);
        callback.onBuy(bytes32(0), market, 0, 0, 0, owner, abi.encode(blueMarketParams));
    }

    function testOnBuyRevertsIfBuyerIsNotOwner() public {
        vm.expectRevert(IBlueBuyCallback.NotOwnerBuyer.selector);
        vm.prank(address(midnight));
        callback.onBuy(bytes32(0), market, 0, 0, 0, address(callback), abi.encode(blueMarketParams));
    }

    function testOnBuyRevertsIfLoanTokenIsInconsistent() public {
        blueMarketParams.loanToken = address(otherToken);

        vm.expectRevert(IBlueBuyCallback.InconsistentLoanToken.selector);
        vm.prank(address(midnight));
        callback.onBuy(bytes32(0), market, 0, 0, 0, owner, abi.encode(blueMarketParams));
    }
}

contract MockMidnight {}

contract MockBlue is IBlue {
    mapping(address authorizer => mapping(address authorized => bool)) public isAuthorized;
    address public recordedOnBehalf;
    address public recordedReceiver;
    address public recordedLoanToken;
    uint256 public recordedAssets;
    uint256 public recordedShares;

    function setAuthorization(address authorized, bool newIsAuthorized) external {
        isAuthorized[msg.sender][authorized] = newIsAuthorized;
    }

    function withdraw(
        BlueMarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256) {
        recordedOnBehalf = onBehalf;
        recordedReceiver = receiver;
        recordedLoanToken = marketParams.loanToken;
        recordedAssets = assets;
        recordedShares = shares;

        ERC20(marketParams.loanToken).transfer(receiver, assets);
        return (assets, shares);
    }
}
