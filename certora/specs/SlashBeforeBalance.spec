// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => NONDET;
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;

    function slash(bytes32 id, address user) internal => slashSummary(id, user);

    // Bypass the hook update when calling debtOf, because it only looks at the negative part of the balance.
    // Note that this also summarizes the external view function debtOf, which is thus skipped by the readAfterSlash rule.
    function debtOf(bytes32 id, address user) internal returns (uint256) => debtOfSummary(id, user);
}

/// GHOSTS ///

// Track the lossIndex at which each user was last slashed.
persistent ghost mapping(bytes32 => mapping(address => uint128)) slashedAtLossIndex;

// Track whether a positive balance was read without prior slash.
persistent ghost bool balanceReadWithoutSlash;

// Track whether a positive balance was written without prior slash.
persistent ghost bool balanceWrittenWithoutSlash;

function slashSummary(bytes32 id, address user) {
    slashedAtLossIndex[id][user] = currentContract.obligationState[id].lossIndex;
}

function debtOfSummary(bytes32 id, address user) returns uint256 {
    int256 balance = currentContract.position[id][user].balance;
    mathint debt = balance < 0 ? -balance : 0;
    return assert_uint256(debt);
}

/// HOOKS ///

// Positive balances must only be read after slash at the current lossIndex.
hook Sload int256 value position[KEY bytes32 id][KEY address user].balance {
    if (slashedAtLossIndex[id][user] != currentContract.obligationState[id].lossIndex && value > 0) {
        balanceReadWithoutSlash = true;
    }
}

// Positive balances must only be written after slash at the current lossIndex.
// This also covers zero-to-positive transitions: when newValue > 0, slash is required
// even if oldValue <= 0, ensuring the user's lossIndex is refreshed first.
hook Sstore position[KEY bytes32 id][KEY address user].balance int256 newValue (int256 oldValue) {
    if (slashedAtLossIndex[id][user] != currentContract.obligationState[id].lossIndex && (oldValue > 0 || newValue > 0)) {
        balanceWrittenWithoutSlash = true;
    }
}

/// RULES ///

// View functions that read balanceOf don't call slash (they can't mutate state).
rule balanceReadAfterSlash(method f, env e, calldataarg args) filtered { f -> f.selector != sig:balanceOf(bytes32, address).selector && f.selector != sig:balanceOfAfterSlashing(bytes32, address).selector && f.selector != sig:isHealthy(Midnight.Obligation, bytes32, address).selector } {
    require !balanceReadWithoutSlash, "initialize the ghost variable";
    f(e, args);
    assert !balanceReadWithoutSlash;
}

rule balanceWrittenAfterSlash(method f, env e, calldataarg args) {
    require !balanceWrittenWithoutSlash, "initialize the ghost variable";
    f(e, args);
    assert !balanceWrittenWithoutSlash;
}
