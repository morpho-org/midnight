// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function pendingFee(bytes32 id, address user) external returns (uint128) envfree;
}

strong invariant noRemainingContinuousFeeWithoutDebt(bytes32 id, address user)
    debtOf(id, user) == 0 => pendingFee(id, user) == 0;
