// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
}

rule debtOfSummaryEquivalence(bytes32 id, address user) {
    int256 balance = currentContract.position[id][user].balance;
    mathint expectedDebt = balance <= 0 ? -balance : 0;
    mathint actualDebt = debtOf@withrevert(id, user);
    assert !lastReverted;
    assert actualDebt == expectedDebt;
}
