// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {IERC20, SafeTransferLib} from "../src/libraries/SafeTransferLib.sol";

/// @dev Token not returning any boolean.
contract ERC20WithoutBoolean {
    function transfer(address to, uint256 value) external {}
    function transferFrom(address from, address to, uint256 value) external {}
}

/// @dev Token returning false.
contract ERC20False {
    function transfer(address to, uint256 value) external returns (bool res) {}
    function transferFrom(address from, address to, uint256 value) external returns (bool res) {}
}

/// @dev Token reverting with a reason string.
contract ERC20RevertReason {
    function transfer(address, uint256) external pure {
        revert("transfer revert reason");
    }

    function transferFrom(address, address, uint256) external pure {
        revert("transferFrom revert reason");
    }
}

/// @dev Token reverting without a reason string.
contract ERC20RevertNoReason {
    function transfer(address, uint256) external pure {
        revert();
    }

    function transferFrom(address, address, uint256) external pure {
        revert();
    }
}

/// @dev Normal token.
contract ERC20True {
    fallback() external {
        // return true.
        assembly {
            mstore(0, 1)
            return(0, 32)
        }
    }
}

contract SafeTransferLibTest is Test {
    ERC20True public tokenTrue;
    ERC20False public tokenFalse;
    ERC20WithoutBoolean public tokenWithoutBoolean;
    ERC20RevertReason public tokenRevertReason;
    ERC20RevertNoReason public tokenRevertNoReason;

    function setUp() public {
        tokenTrue = new ERC20True();
        tokenFalse = new ERC20False();
        tokenWithoutBoolean = new ERC20WithoutBoolean();
        tokenRevertReason = new ERC20RevertReason();
        tokenRevertNoReason = new ERC20RevertNoReason();
    }

    function testSafeTransferNoCode() public {
        vm.expectRevert(SafeTransferLib.NoCode.selector);
        this.safeTransfer(address(1), address(1), 1);
    }

    function testSafeTransferReverted() public {
        vm.expectRevert("transfer revert reason");
        this.safeTransfer(address(tokenRevertReason), address(1), 1);
    }

    function testSafeTransferRevertedNoReason() public {
        vm.expectRevert(bytes(""));
        this.safeTransfer(address(tokenRevertNoReason), address(1), 1);
    }

    function testSafeTransferReturnedFalse() public {
        vm.expectRevert(SafeTransferLib.TransferReturnedFalse.selector);
        this.safeTransfer(address(tokenFalse), address(1), 1);
    }

    function testSafeTransferNormal(address to, uint256 value) public {
        vm.expectCall(address(tokenTrue), abi.encodeCall(IERC20.transfer, (to, value)));
        this.safeTransfer(address(tokenTrue), to, value);
    }

    function testSafeTransferNoBoolean(address to, uint256 value) public {
        vm.expectCall(address(tokenWithoutBoolean), abi.encodeCall(IERC20.transfer, (to, value)));
        this.safeTransfer(address(tokenWithoutBoolean), to, value);
    }

    function testSafeTransferFromNoCode() public {
        vm.expectRevert(SafeTransferLib.NoCode.selector);
        this.safeTransferFrom(address(1), address(1), address(1), 1);
    }

    function testSafeTransferFromReverted() public {
        vm.expectRevert("transferFrom revert reason");
        this.safeTransferFrom(address(tokenRevertReason), address(1), address(1), 1);
    }

    function testSafeTransferFromRevertedNoReason() public {
        vm.expectRevert(bytes(""));
        this.safeTransferFrom(address(tokenRevertNoReason), address(1), address(1), 1);
    }

    function testSafeTransferFromReturnedFalse() public {
        vm.expectRevert(SafeTransferLib.TransferFromReturnedFalse.selector);
        this.safeTransferFrom(address(tokenFalse), address(1), address(1), 1);
    }

    function testSafeTransferFrom(address from, address to, uint256 value) public {
        vm.expectCall(address(tokenTrue), abi.encodeCall(IERC20.transferFrom, (from, to, value)));
        this.safeTransferFrom(address(tokenTrue), from, to, value);
    }

    function testSafeTransferFromNoBoolean(address from, address to, uint256 value) public {
        vm.expectCall(address(tokenWithoutBoolean), abi.encodeCall(IERC20.transferFrom, (from, to, value)));
        this.safeTransferFrom(address(tokenWithoutBoolean), from, to, value);
    }

    /* HELPERS */

    function safeTransfer(address token, address to, uint256 value) external {
        SafeTransferLib.safeTransfer(token, to, value);
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) external {
        SafeTransferLib.safeTransferFrom(token, from, to, value);
    }
}
