// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => NONDET;
    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;

    function slash(bytes32 id, address user) internal => slashSummary(id, user);
}

/// GHOSTS ///

// Track the lossIndex at which each user was last slashed.
persistent ghost mapping(bytes32 => mapping(address => uint128)) slashedAtLossIndex;

// Track whether credit was read without prior slash.
persistent ghost bool creditReadWithoutSlash;

// Track whether credit was written without prior slash.
persistent ghost bool creditWrittenWithoutSlash;

function slashSummary(bytes32 id, address user) {
    slashedAtLossIndex[id][user] = currentContract.obligationState[id].lossIndex;
}

/// HOOKS ///

// Credit must only be read after slash at the current lossIndex.
hook Sload uint128 value position[KEY bytes32 id][KEY address user].credit {
    if (slashedAtLossIndex[id][user] != currentContract.obligationState[id].lossIndex && value > 0) {
        creditReadWithoutSlash = true;
    }
}

// Credit must only be written after slash at the current lossIndex.
// This also covers zero-to-positive transitions: when newValue > 0, slash is required
// even if oldValue == 0, ensuring the user's lossIndex is refreshed first.
hook Sstore position[KEY bytes32 id][KEY address user].credit uint128 newValue (uint128 oldValue) {
    if (slashedAtLossIndex[id][user] != currentContract.obligationState[id].lossIndex && (oldValue > 0 || newValue > 0)) {
        creditWrittenWithoutSlash = true;
    }
}

/// RULES ///

// View functions that read credit don't call slash (they can't mutate state).
rule creditReadAfterSlash(method f, env e, calldataarg args) filtered { f -> f.selector != sig:creditOf(bytes32, address).selector && f.selector != sig:creditAfterSlashing(bytes32, address).selector } {
    require !creditReadWithoutSlash, "initialize the ghost variable";
    f(e, args);
    assert !creditReadWithoutSlash;
}

rule creditWrittenAfterSlash(method f, env e, calldataarg args) {
    require !creditWrittenWithoutSlash, "initialize the ghost variable";
    f(e, args);
    assert !creditWrittenWithoutSlash;
}
