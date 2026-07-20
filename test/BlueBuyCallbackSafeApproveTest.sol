// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {BlueBuyCallback} from "../src/periphery/BlueBuyCallback.sol";
import {IBlueBuyCallback} from "../src/periphery/interfaces/IBlueBuyCallback.sol";

contract BlueBuyCallbackSafeApproveTest is Test {
    address internal spender = makeAddr("spender");
    BlueBuyCallbackHarness internal callback;

    function setUp() public {
        callback = new BlueBuyCallbackHarness(address(new MockBlue()));
    }

    function testSafeApproveSupportsNoReturnValue(uint256 value) public {
        NoReturnApproveToken token = new NoReturnApproveToken();

        callback.exposedSafeApprove(address(token), spender, value);

        assertEq(token.allowance(address(callback), spender), value);
    }

    function testSafeApproveRevertsIfApproveReturnsFalse() public {
        FalseApproveToken token = new FalseApproveToken();

        vm.expectRevert(IBlueBuyCallback.ApproveReturnedFalse.selector);
        callback.exposedSafeApprove(address(token), spender, 1);
    }

    function testSafeApproveBubblesApproveRevert() public {
        RevertingApproveToken token = new RevertingApproveToken();

        vm.expectRevert(RevertingApproveToken.ApproveReverted.selector);
        callback.exposedSafeApprove(address(token), spender, 1);
    }

    function testForceApproveMaxResetsExistingAllowance() public {
        USDTLikeApproveToken token = new USDTLikeApproveToken();
        token.setAllowance(address(callback), spender, 1);

        callback.exposedForceApproveMax(address(token), spender);

        assertEq(token.approveCalls(), 2);
        assertEq(token.allowance(address(callback), spender), type(uint256).max);
    }

    function testForceApproveMaxSkipsLargeExistingAllowance() public {
        TrackingApproveToken token = new TrackingApproveToken();
        uint256 allowance = type(uint96).max / 2;
        token.setAllowance(address(callback), spender, allowance);

        callback.exposedForceApproveMax(address(token), spender);

        assertEq(token.approveCalls(), 0);
        assertEq(token.allowance(address(callback), spender), allowance);
    }
}

contract BlueBuyCallbackHarness is BlueBuyCallback {
    constructor(address blue) BlueBuyCallback(address(this), address(0), blue) {}

    function exposedSafeApprove(address token, address spender, uint256 value) external {
        super.safeApprove(token, spender, value);
    }

    function exposedForceApproveMax(address token, address spender) external {
        super.forceApproveMax(token, spender);
    }
}

contract MockBlue {
    function setAuthorization(address, bool) external {}
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
