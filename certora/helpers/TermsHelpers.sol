// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Terms, Term, IERC20} from "../../src/Terms.sol";

contract TermsHelpers is Terms {
    function balanceOf(address token, address account) external view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }

    function id(Term memory term) external pure returns (bytes32) {
        return _id(term);
    }
}
