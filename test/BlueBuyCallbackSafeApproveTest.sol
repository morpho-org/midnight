// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ApproveLib} from "../src/periphery/BlueBuyCallback/ApproveLib.sol";

contract BlueBuyCallbackSafeApproveTest is Test {
    address internal spender = makeAddr("spender");

    function testSafeApproveSupportsNoReturnValue(uint256 value) public {
        NoReturnApproveToken token = new NoReturnApproveToken();

        this.safeApprove(address(token), spender, value);

        assertEq(token.allowance(address(this), spender), value);
    }

    function testSafeApproveRevertsIfApproveReturnsFalse() public {
        FalseApproveToken token = new FalseApproveToken();

        vm.expectRevert(ApproveLib.ApproveReturnedFalse.selector);
        this.safeApprove(address(token), spender, 1);
    }

    function testSafeApproveBubblesApproveRevert() public {
        RevertingApproveToken token = new RevertingApproveToken();

        vm.expectRevert(RevertingApproveToken.ApproveReverted.selector);
        this.safeApprove(address(token), spender, 1);
    }

    function testForceApproveMaxResetsExistingAllowance() public {
        USDTLikeApproveToken token = new USDTLikeApproveToken();
        token.setAllowance(address(this), spender, 1);

        this.forceApproveMax(address(token), spender);

        assertEq(token.approveCalls(), 2);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
    }

    function testForceApproveMaxSkipsLargeExistingAllowance() public {
        TrackingApproveToken token = new TrackingApproveToken();
        uint256 allowance = type(uint96).max / 2;
        token.setAllowance(address(this), spender, allowance);

        this.forceApproveMax(address(token), spender);

        assertEq(token.approveCalls(), 0);
        assertEq(token.allowance(address(this), spender), allowance);
    }

    /* HELPERS */

    function safeApprove(address token, address spender_, uint256 value) external {
        ApproveLib.safeApprove(token, spender_, value);
    }

    function forceApproveMax(address token, address spender_) external {
        ApproveLib.forceApproveMax(token, spender_);
    }
}

contract NoReturnApproveToken {
    mapping(address owner => mapping(address spender => uint256)) public allowance;

    function approve(address spender, uint256 value) external {
        allowance[msg.sender][spender] = value;
    }
}

contract FalseApproveToken {
    function approve(address, uint256) external pure returns (bool) {
        return false;
    }
}

contract RevertingApproveToken {
    error ApproveReverted();

    function approve(address, uint256) external pure returns (bool) {
        revert ApproveReverted();
    }
}

contract TrackingApproveToken {
    mapping(address owner => mapping(address spender => uint256)) public allowance;
    uint256 public approveCalls;

    function setAllowance(address owner, address spender, uint256 value) external {
        allowance[owner][spender] = value;
    }

    function approve(address spender, uint256 value) external virtual returns (bool) {
        approveCalls++;
        allowance[msg.sender][spender] = value;
        return true;
    }
}

contract USDTLikeApproveToken is TrackingApproveToken {
    function approve(address spender, uint256 value) external override returns (bool) {
        require(value == 0 || allowance[msg.sender][spender] == 0);
        approveCalls++;
        allowance[msg.sender][spender] = value;
        return true;
    }
}
