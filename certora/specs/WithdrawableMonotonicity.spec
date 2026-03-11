// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function withdrawable(bytes32 id) external returns (uint256) envfree;
    function toId(Midnight.Obligation) external returns (bytes32);
}

rule repayIncreasesWithdrawable(env e, Midnight.Obligation obligation, uint256 obligationUnits, address onBehalf) {
    bytes32 id = toId(e, obligation);
    uint256 withdrawableBefore = withdrawable(id);
    repay(e, obligation, obligationUnits, onBehalf);
    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableAfter == withdrawableBefore + obligationUnits;
}

rule liquidateIncreasesWithdrawable(env e, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) {
    bytes32 id = toId(e, obligation);
    uint256 withdrawableBefore = withdrawable(id);
    uint256 seizedResult;
    uint256 repaidResult;
    seizedResult, repaidResult = liquidate(e, obligation, collateralIndex, seizedAssets, repaidUnits, borrower, data);
    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableAfter == withdrawableBefore + repaidResult;
}

rule withdrawDecreasesWithdrawableExactly(env e, Midnight.Obligation obligation, uint256 obligationUnitsInput, uint256 shares, address onBehalf, address receiver) {
    bytes32 id = toId(e, obligation);
    uint256 withdrawableBefore = withdrawable(id);
    uint256 withdrawnUnits;
    uint256 withdrawnShares;
    withdrawnUnits, withdrawnShares = withdraw(e, obligation, obligationUnitsInput, shares, onBehalf, receiver);
    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableAfter == withdrawableBefore - withdrawnUnits;
}

rule withdrawableUnchanged(method f, env e, calldataarg args, bytes32 id)
filtered {
    f -> !f.isView
        && f.selector != sig:repay(Midnight.Obligation, uint256, address).selector
        && f.selector != sig:liquidate(Midnight.Obligation, uint256, uint256, uint256, address, bytes).selector
        && f.selector != sig:withdraw(Midnight.Obligation, uint256, uint256, address, address).selector
} {
    uint256 withdrawableBefore = withdrawable(id);
    f(e, args);
    uint256 withdrawableAfter = withdrawable(id);
    assert withdrawableAfter == withdrawableBefore;
}
