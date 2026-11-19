// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {IMorpho, MarketParams, Authorization, Signature} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {AUTHORIZATION_TYPEHASH, DOMAIN_TYPEHASH} from "../lib/morpho-blue/src/libraries/ConstantsLib.sol";
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

    function testSetAuthorizationWithSig() public {
        uint256 ownerPrivateKey = 1;
        address signer = vm.addr(ownerPrivateKey);
        address authorized = makeAddr("authorized");
        BlueSwapBuyCallback signedCallback = new BlueSwapBuyCallback(signer, address(midnight), address(blue));
        Authorization memory authorization = Authorization(signer, authorized, true, 0, block.timestamp);
        Signature memory signature = _signAuthorization(ownerPrivateKey, address(signedCallback), authorization);

        vm.expectEmit(address(signedCallback));
        emit IBlueSwapBuyCallback.SetAuthorizationWithSig(address(this), 0);
        signedCallback.setAuthorizationWithSig(authorization, signature);

        assertTrue(blue.isAuthorized(address(signedCallback), authorized));
        assertEq(signedCallback.nonce(), 1);
    }

    function testSetAuthorizationWithSigRevertsIfExpired() public {
        uint256 ownerPrivateKey = 1;
        address signer = vm.addr(ownerPrivateKey);
        BlueSwapBuyCallback signedCallback = new BlueSwapBuyCallback(signer, address(midnight), address(blue));
        Authorization memory authorization = Authorization(signer, makeAddr("authorized"), true, 0, block.timestamp - 1);
        Signature memory signature = _signAuthorization(ownerPrivateKey, address(signedCallback), authorization);

        vm.expectRevert(IBlueSwapBuyCallback.AuthorizationExpired.selector);
        signedCallback.setAuthorizationWithSig(authorization, signature);
    }

    function testSetAuthorizationWithSigAllowsNoOp() public {
        uint256 ownerPrivateKey = 1;
        address signer = vm.addr(ownerPrivateKey);
        address authorized = makeAddr("authorized");
        BlueSwapBuyCallback signedCallback = new BlueSwapBuyCallback(signer, address(midnight), address(blue));
        Authorization memory authorization = Authorization(signer, authorized, false, 0, block.timestamp);
        Signature memory signature = _signAuthorization(ownerPrivateKey, address(signedCallback), authorization);

        signedCallback.setAuthorizationWithSig(authorization, signature);

        assertFalse(blue.isAuthorized(address(signedCallback), authorized));
        assertEq(signedCallback.nonce(), 1);
    }

    function testSetAuthorizationWithSigRevertsIfNonceIsReused() public {
        uint256 ownerPrivateKey = 1;
        address signer = vm.addr(ownerPrivateKey);
        BlueSwapBuyCallback signedCallback = new BlueSwapBuyCallback(signer, address(midnight), address(blue));
        Authorization memory authorization = Authorization(signer, makeAddr("authorized"), true, 0, block.timestamp);
        Signature memory signature = _signAuthorization(ownerPrivateKey, address(signedCallback), authorization);
        signedCallback.setAuthorizationWithSig(authorization, signature);

        vm.expectRevert(IBlueSwapBuyCallback.InvalidNonce.selector);
        signedCallback.setAuthorizationWithSig(authorization, signature);
    }

    function testSetAuthorizationWithSigRevertsIfSignerIsNotOwner() public {
        uint256 ownerPrivateKey = 1;
        address signer = vm.addr(ownerPrivateKey);
        BlueSwapBuyCallback signedCallback = new BlueSwapBuyCallback(signer, address(midnight), address(blue));
        Authorization memory authorization = Authorization(signer, makeAddr("authorized"), true, 0, block.timestamp);
        Signature memory signature = _signAuthorization(2, address(signedCallback), authorization);

        vm.expectRevert(IBlueSwapBuyCallback.InvalidSignature.selector);
        signedCallback.setAuthorizationWithSig(authorization, signature);
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

contract SwapMockMidnight {}
