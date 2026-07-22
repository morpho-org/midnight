// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {IMorpho, MarketParams, Authorization, Signature} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {AUTHORIZATION_TYPEHASH, DOMAIN_TYPEHASH} from "../lib/morpho-blue/src/libraries/ConstantsLib.sol";
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
        vm.expectRevert(IBlueBuyCallback.NotOwner.selector);
        callback.setAuthorization(makeAddr("authorized"), true);
    }

    function testSetAuthorizationWithSig() public {
        uint256 ownerPrivateKey = 1;
        address signer = vm.addr(ownerPrivateKey);
        address authorized = makeAddr("authorized");
        BlueBuyCallback signedCallback = new BlueBuyCallback(signer, address(midnight), address(blue));
        Authorization memory authorization = Authorization(signer, authorized, true, 0, block.timestamp);
        Signature memory signature = _signAuthorization(ownerPrivateKey, address(signedCallback), authorization);

        vm.expectEmit(address(signedCallback));
        emit IBlueBuyCallback.SetAuthorizationWithSig(address(this), 0);
        signedCallback.setAuthorizationWithSig(authorization, signature);

        assertTrue(blue.isAuthorized(address(signedCallback), authorized));
        assertEq(signedCallback.nonce(), 1);
    }

    function testSetAuthorizationWithSigRevertsIfExpired() public {
        uint256 ownerPrivateKey = 1;
        address signer = vm.addr(ownerPrivateKey);
        BlueBuyCallback signedCallback = new BlueBuyCallback(signer, address(midnight), address(blue));
        Authorization memory authorization = Authorization(signer, makeAddr("authorized"), true, 0, block.timestamp - 1);
        Signature memory signature = _signAuthorization(ownerPrivateKey, address(signedCallback), authorization);

        vm.expectRevert(IBlueBuyCallback.AuthorizationExpired.selector);
        signedCallback.setAuthorizationWithSig(authorization, signature);
    }

    function testSetAuthorizationWithSigAllowsNoOp() public {
        uint256 ownerPrivateKey = 1;
        address signer = vm.addr(ownerPrivateKey);
        address authorized = makeAddr("authorized");
        BlueBuyCallback signedCallback = new BlueBuyCallback(signer, address(midnight), address(blue));
        Authorization memory authorization = Authorization(signer, authorized, false, 0, block.timestamp);
        Signature memory signature = _signAuthorization(ownerPrivateKey, address(signedCallback), authorization);

        signedCallback.setAuthorizationWithSig(authorization, signature);

        assertFalse(blue.isAuthorized(address(signedCallback), authorized));
        assertEq(signedCallback.nonce(), 1);
    }

    function testSetAuthorizationWithSigRevertsIfNonceIsReused() public {
        uint256 ownerPrivateKey = 1;
        address signer = vm.addr(ownerPrivateKey);
        BlueBuyCallback signedCallback = new BlueBuyCallback(signer, address(midnight), address(blue));
        Authorization memory authorization = Authorization(signer, makeAddr("authorized"), true, 0, block.timestamp);
        Signature memory signature = _signAuthorization(ownerPrivateKey, address(signedCallback), authorization);
        signedCallback.setAuthorizationWithSig(authorization, signature);

        vm.expectRevert(IBlueBuyCallback.InvalidNonce.selector);
        signedCallback.setAuthorizationWithSig(authorization, signature);
    }

    function testSetAuthorizationWithSigRevertsIfSignerIsNotOwner() public {
        uint256 ownerPrivateKey = 1;
        address signer = vm.addr(ownerPrivateKey);
        BlueBuyCallback signedCallback = new BlueBuyCallback(signer, address(midnight), address(blue));
        Authorization memory authorization = Authorization(signer, makeAddr("authorized"), true, 0, block.timestamp);
        Signature memory signature = _signAuthorization(2, address(signedCallback), authorization);

        vm.expectRevert(IBlueBuyCallback.InvalidSignature.selector);
        signedCallback.setAuthorizationWithSig(authorization, signature);
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

    function testMaxBuyerAssetsReturnsSupplyAssets(uint256 supplyAssets, uint256 otherSupplyAssets) public {
        supplyAssets = bound(supplyAssets, 0, 1e30);
        otherSupplyAssets = bound(otherSupplyAssets, 0, 1e30);
        deal(address(loanToken), address(this), supplyAssets + otherSupplyAssets);
        require(loanToken.approve(address(blue), supplyAssets + otherSupplyAssets));
        if (supplyAssets > 0) blue.supply(blueMarketParams, supplyAssets, 0, address(callback), hex"");
        if (otherSupplyAssets > 0) blue.supply(blueMarketParams, otherSupplyAssets, 0, address(this), hex"");

        uint256 result = callback.maxBuyerAssets(bytes32(0), market, owner, abi.encode(blueMarketParams));

        assertEq(result, supplyAssets);
    }

    function testMaxBuyerAssetsRevertsIfBuyerIsNotOwner(address buyer) public {
        vm.assume(buyer != owner);
        vm.expectRevert(IBlueBuyCallback.NotOwnerBuyer.selector);
        callback.maxBuyerAssets(bytes32(0), market, buyer, abi.encode(blueMarketParams));
    }

    function testMaxBuyerAssetsRevertsIfLoanTokenIsInconsistent() public {
        blueMarketParams.loanToken = address(otherToken);

        vm.expectRevert(IBlueBuyCallback.InconsistentLoanToken.selector);
        callback.maxBuyerAssets(bytes32(0), market, owner, abi.encode(blueMarketParams));
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

    function _signAuthorization(uint256 privateKey, address verifyingContract, Authorization memory authorization)
        internal
        view
        returns (Signature memory signature)
    {
        bytes32 hashStruct = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, authorization));
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, verifyingContract));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, hashStruct));
        (signature.v, signature.r, signature.s) = vm.sign(privateKey, digest);
    }
}

contract MockMidnight {}
