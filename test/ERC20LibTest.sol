// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC20Lib} from "../src/periphery/blue-buy-callback/ERC20Lib.sol";

contract ERC20LibTest is Test {
    address internal spender = makeAddr("spender");

    function testSafeApproveSupportsNoReturnValue(uint256 value) public {
        NoReturnApproveToken token = new NoReturnApproveToken();

        this.safeApprove(address(token), spender, value);

        assertEq(token.allowance(address(this), spender), value);
    }

    function testSafeApproveRevertsIfApproveReturnsFalse() public {
        FalseApproveToken token = new FalseApproveToken();

        vm.expectRevert(ERC20Lib.ApproveReturnedFalse.selector);
        this.safeApprove(address(token), spender, 1);
    }

    function testSafeApproveBubblesApproveRevert() public {
        RevertingApproveToken token = new RevertingApproveToken();

        vm.expectRevert(RevertingApproveToken.ApproveReverted.selector);
        this.safeApprove(address(token), spender, 1);
    }

    /* HELPERS */

    function safeApprove(address token, address spender_, uint256 value) external {
        ERC20Lib.safeApprove(token, spender_, value);
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
