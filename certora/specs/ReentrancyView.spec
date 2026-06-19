// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // ignore changes done by touchMarket and _updatePosition; the state after these calls is still
    // valid even if they changed the state.
    function touchMarket(Midnight.Market memory) internal returns (bytes32) => NONDET;
    function _updatePosition(Midnight.Market memory, bytes32, address) internal returns (uint128, uint128, uint128) => NONDET;

    // Ignore the transient stores of LIQUIDATION_LOCK via the tExchange method.
    // These do not affect the persistent state inspected by this spec.
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;
}

// True when at least one slot was written.
persistent ghost bool storageChanged;

// True when at least one STATICCALL is executed after a storage change.
persistent ghost bool staticCallAfterStore;

// True when at least one slot is changed after a STATICCALL is executed after a storage change.
persistent ghost bool staticCallUnsafe;

hook ALL_SSTORE(uint _, uint _) {
    storageChanged = true;
    if (staticCallAfterStore) {
        staticCallUnsafe = true;
    }
}

hook ALL_TSTORE(uint _, uint _) {
    storageChanged = true;
    if (staticCallAfterStore) {
        staticCallUnsafe = true;
    }
}

hook STATICCALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    if (storageChanged) {
        staticCallAfterStore = true;
    }
}

// Check that all external view calls are done before the first store or after the last store.
// Additionally changes by _updatePosition and touchMarket are ignored because they ensure the state is valid again.
rule reentrancyViewSafe(method f, env e, calldataarg data) {
    require(!storageChanged && !staticCallAfterStore && !staticCallUnsafe, "set up the initial ghost state");

    f(e, data);

    assert !staticCallUnsafe;
}
