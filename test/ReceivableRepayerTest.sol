// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {ReceivableTokenTest} from "./ReceivableTokenTest.sol";
import {ReceivableRepayer} from "../src/periphery/receivable-token/ReceivableRepayer.sol";
import {IReceivableToken} from "../src/periphery/receivable-token/interfaces/IReceivableToken.sol";
import {MerkleProofLib} from "../src/periphery/receivable-token/libraries/MerkleProofLib.sol";
import {Market} from "../src/interfaces/IMidnight.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";

contract ReceivableRepayerTest is ReceivableTokenTest {
    ReceivableRepayer internal repayer;
    uint256 internal constant DEBT = 100e18;
    uint256 internal constant COLLATERAL = 300e18;

    function _prepare() internal {
        repayer = new ReceivableRepayer(address(midnight));
        _mint(COLLATERAL);
        vm.startPrank(minter);
        midnight.setIsAuthorized(address(repayer), true, minter);
        midnight.supplyCollateral(_market(), 0, COLLATERAL, minter);
        token.setRate(2 * WAD / 3);
        vm.stopPrank();
        take(DEBT, minter, _buyOffer(_market()));
        _pay(token, COLLATERAL);
    }

    function _repay(uint256 units) internal {
        vm.prank(minter);
        midnight.repay(_market(), units, minter, address(repayer), abi.encode(uint256(0)));
    }

    function testFullRepayRounding() public {
        _prepare();
        uint256 balanceBefore = loanToken.balanceOf(minter);
        uint256 amount = (DEBT * WAD + token.rate() - 1) / token.rate();
        _repay(DEBT);
        assertEq(midnight.debt(toId(_market()), minter), 0, "debt");
        assertEq(midnight.collateral(toId(_market()), minter, 0), COLLATERAL - amount, "collateral");
        assertEq(loanToken.balanceOf(minter), balanceBefore, "no dust below par");
        assertEq(token.balanceOf(address(repayer)), 0, "no tokens");
        assertEq(token.transientSupply(), 0, "settled");
        assertEq(loanToken.balanceOf(address(repayer)), 0, "no assets");
        assertEq(loanToken.allowance(address(repayer), address(midnight)), 0, "approval spent");
    }

    function testPartialRepay() public {
        _prepare();
        _repay(DEBT / 2);
        assertEq(midnight.debt(toId(_market()), minter), DEBT / 2, "remaining debt");
        assertGt(midnight.collateral(toId(_market()), minter, 0), 0, "remaining collateral");
        assertTrue(midnight.isHealthy(_market(), toId(_market()), minter), "healthy");
    }

    function testNotMidnight() public {
        _prepare();
        vm.expectRevert(ReceivableRepayer.NotMidnight.selector);
        repayer.onRepay(toId(_market()), _market(), DEBT, minter, abi.encode(uint256(0)));
    }

    function testHookOutsideRepay() public {
        _prepare();
        vm.prank(address(token));
        vm.expectRevert(ReceivableRepayer.UnexpectedToken.selector);
        repayer.onReceivableTokenReceived(address(midnight), 1);
    }

    function testAttackerCannotSelectVictim() public {
        _prepare();
        vm.prank(minter);
        token.setRoot(ROOT_C, MerkleProofLib.leaf(otherMinter, COLLATERAL));
        vm.startPrank(otherMinter);
        token.mint(ROOT_C, COLLATERAL, COLLATERAL, emptyProof);
        token.approve(address(midnight), COLLATERAL);
        Market memory market = _market();
        midnight.setIsAuthorized(address(repayer), true, otherMinter);
        midnight.supplyCollateral(market, 0, COLLATERAL, otherMinter);
        vm.stopPrank();
        take(DEBT, otherMinter, _buyOffer(market));
        vm.prank(otherMinter);
        midnight.repay(market, DEBT, otherMinter, address(repayer), abi.encode(uint256(0), minter));
        assertEq(midnight.debt(toId(market), otherMinter), 0, "attacker repays own debt");
        assertEq(midnight.collateral(toId(market), minter, 0), COLLATERAL, "victim collateral untouched");
        assertEq(midnight.debt(toId(market), minter), DEBT, "victim debt untouched");
    }

    function testInsufficientCash() public {
        _prepare();
        deal(address(loanToken), address(token), 0);
        vm.expectRevert(IReceivableToken.InsufficientCash.selector);
        _repay(DEBT);
    }

    function testZeroRate() public {
        _prepare();
        vm.prank(minter);
        token.setRate(0);
        vm.expectRevert(ReceivableRepayer.ZeroRate.selector);
        _repay(DEBT);
    }

    function testMismatchedAsset() public {
        _prepare();
        vm.mockCall(address(token), abi.encodeCall(token.asset, ()), abi.encode(address(otherToken)));
        vm.expectRevert(ReceivableRepayer.InconsistentLoanToken.selector);
        _repay(DEBT);
    }

    function testMalformedData() public {
        _prepare();
        vm.prank(minter);
        vm.expectRevert();
        midnight.repay(_market(), DEBT, minter, address(repayer), "");
    }

    function testZeroRepay() public {
        _prepare();
        _repay(0);
        assertEq(midnight.debt(toId(_market()), minter), DEBT, "debt unchanged");
        assertEq(midnight.collateral(toId(_market()), minter, 0), COLLATERAL, "collateral unchanged");
    }
}
