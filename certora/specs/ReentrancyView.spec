// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // ignore changes done by touchMarket and _updatePosition; the state after these calls is still
    // valid even if they changed the state.
    function touchMarket(Midnight.Market memory) internal returns (bytes32) => NONDET;
    function _updatePosition(Midnight.Market memory, bytes32, address) internal returns (uint128, uint128, uint128) => NONDET;
}

function ignoredBoolStaticcall() returns bool {
    ignoredStaticcall = true;
    bool value;
    return value;
}

function ignoredUintStaticcall() returns uint256 {
    ignoredStaticcall = true;
    uint256 value;
    return value;
}

persistent ghost bool ignoredStaticcall;

// True when at least one slot was written.
persistent ghost bool storageChanged;

// True when at least one STATICCALL is executed after a storage change.
persistent ghost bool staticCallAfterSStore;

// True when at least one slot is changed after a STATICCALL is executed after a storage change.
persistent ghost bool staticCallUnsafe;

hook ALL_SSTORE(uint _, uint _) {
    storageChanged = true;
    if (staticCallAfterSStore) {
        staticCallUnsafe = true;
    }
}

hook ALL_TSTORE(uint _, uint _) {
    storageChanged = true;
    if (staticCallAfterSStore) {
        staticCallUnsafe = true;
    }
}

hook STATICCALL(uint256 g, address addr, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    // address(1) is ignored because it's the ecrecover function.
    if (!ignoredStaticcall && storageChanged && addr != 0x1) {
        staticCallAfterSStore = true;
    }
    ignoredStaticcall = false;
}

// Check that there are no reentrancy unsafe calls except potentially for balanceOf on the asset, realAssets on the adapters and canReceiveShares, canSendShares, canReceiveAssets and canSendAssets on the gates, and isInRegistry on adapter registry.
rule reentrancyViewSafe(method f, env e, calldataarg data) {
    require ignoredStaticcall == false, "setup ghost state";
    require storageChanged == false, "setup ghost state";
    require staticCallAfterSStore == false, "setup ghost state";
    require staticCallUnsafe == false, "setup ghost state";

    f(e, data);

    assert !staticCallUnsafe;
}
