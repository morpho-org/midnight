// SPDX-License-Identifier: GPL-2.0-or-later

// Property: "Post maturity, the liquidation is locked or the debt cannot increase."

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function debtOf(bytes32 id, address user) external returns (uint128) envfree;
    function liquidationLocked(bytes32 id, address user) external returns (bool) envfree;
    function Utils.hashMarket(Midnight.Market) external returns (bytes32) envfree;

    // Deterministic, injective id linking a call-site market to its maturity.
    function IdLib.toId(Midnight.Market memory market, uint256, address) internal returns (bytes32) => summaryToId(market);
    function IdLib.storeInCode(Midnight.Market memory, uint256) internal returns (address) => NONDET;
}

/// HELPERS ///

function summaryToId(Midnight.Market market) returns bytes32 {
    return Utils.hashMarket(market);
}

/// RULE ///

rule lockedOrDebtCannotIncreasePostMaturity(env e, method f, calldataarg args, Midnight.Market market, address user) filtered { f -> !f.isView } {
    bytes32 id = summaryToId(market);

    mathint debtBefore = debtOf(id, user);

    f(e, args);

    assert e.block.timestamp > to_mathint(market.maturity) => (liquidationLocked(id, user) || debtOf(id, user) <= debtBefore);
}
