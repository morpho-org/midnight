// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => NONDET;

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;

    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;

    // Summarize _updatePosition so that its credit reads/writes do not fire the hooks below.
    function _updatePosition(Midnight.Obligation memory, bytes32 id, address user) internal => summaryUpdatePosition(id, user);
    function hasCredit(bytes32 id, address user) internal returns (bool) => summaryHasCredit(id, user);
}

/// GHOSTS ///

/// Whether _updatePosition was called for (id, user) in this transaction.
persistent ghost mapping(bytes32 => mapping(address => bool)) updated;

/// Whether credit was stored before _updatePosition was called for (id, user).
persistent ghost mapping(bytes32 => mapping(address => bool)) creditStoredBeforeUpdate;

/// Whether credit was loaded before _updatePosition was called for (id, user).
persistent ghost mapping(bytes32 => mapping(address => bool)) creditLoadedBeforeUpdate;

/// SUMMARIES ///

/// Summary for _updatePosition: just sets the updated ghost flag.
/// The original function body is replaced, so its internal credit reads/writes do not fire hooks.
function summaryUpdatePosition(bytes32 id, address user) {
    updated[id][user] = true;
}

/// Summary for hasCredit:  circumvent the load hook for credit checks.
function summaryHasCredit(bytes32 id, address user) returns (bool) {
    return currentContract.position[id][user].credit > 0;
}

/// HOOKS ///

hook Sstore position[KEY bytes32 id][KEY address user].credit uint128 newVal (uint128 oldVal) {
    if (!updated[id][user] && newVal != oldVal) {
        creditStoredBeforeUpdate[id][user] = true;
    }
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].credit {
    if (!updated[id][user] && val != 0) {
        creditLoadedBeforeUpdate[id][user] = true;
    }
}

/// RULES ///

/// Check that credit is never stored before _updatePosition is called.
/// The SSTOREs of _updatePosition are ignored (see summary above).
rule creditNotStoredBeforeUpdate(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> !f.isView } {
    require !creditStoredBeforeUpdate[id][user], "initialize the ghost variable";

    f(e, args);

    assert !creditStoredBeforeUpdate[id][user], "credit was stored before _updatePosition was called";
}

/// Check that credit is never loaded before _updatePosition is called.
/// The SLOADs of _updatePosition are ignored (see summary above).
/// TODO check take with another approach.
rule creditNotLoadedBeforeUpdate(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:creditOf(bytes32, address).selector && f.selector != sig:updatePositionView(Midnight.Obligation, bytes32, address).selector && f.selector != sig:position(bytes32, address).selector } {
    require !creditLoadedBeforeUpdate[id][user], "initialize the ghost variable";

    f(e, args);

    assert !creditLoadedBeforeUpdate[id][user], "credit was loaded before _updatePosition was called";
}
