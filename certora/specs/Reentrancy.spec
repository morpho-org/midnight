// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // ignore changes done by touchMarket and _updatePosition; the state after these calls is still
    // valid even if they changed the state.
    function touchMarket(Midnight.Market memory) internal returns (bytes32) => NONDET;
    function _updatePosition(Midnight.Market memory, bytes32, address) internal returns (uint128, uint128, uint128) => NONDET;
}

function ignoredCallVoidSummary() {
    ignoredCall = true;
}

function ignoredCallBoolSummary() returns bool {
    ignoredCall = true;
    bool value;
    return value;
}

function ignoredCallUintPairSummary() returns (uint256, uint256) {
    ignoredCall = true;
    uint256[2] values;
    return (values[0], values[1]);
}

function ignoredCallUintSummary() returns uint256 {
    ignoredCall = true;
    uint256 value;
    return value;
}

// True when at least one slot was written.
persistent ghost bool storageChanged;

persistent ghost bool ignoredCall;
persistent ghost bool hasCallAfterStore;
persistent ghost bool unsafeCall;

hook ALL_SSTORE(uint _, uint _) {
    storageChanged = true;
    if (hasCallAfterStore) {
        unsafeCall = true;
    }
}

hook ALL_TSTORE(uint _, uint _) {
    storageChanged = true;
    if (hasCallAfterStore) {
        unsafeCall = true;
    }
}

hook CALL(uint256 g, address addr, uint256 value, uint256 argsOffset, uint256 argsLength, uint256 retOffset, uint256 retLength) uint256 rc {
    // Ignore calls to tokens and Morpho markets and Metamorpho as they are trusted to not reenter (they have gone through a timelock).
    if (ignoredCall || addr == currentContract) {
        ignoredCall = false;
    } else {
        if (storageChanged) {
            hasCallAfterStore = true;
        }
    }
}

// Check that there are no untrusted external calls, ensuring notably reentrancy safety.
rule reentrancySafe(method f, env e, calldataarg data) {
    require (!storageChanged && !ignoredCall && !hasCallAfterStore && !unsafeCall, "set up the initial ghost state");
    f(e,data);
    assert !unsafeCall;
}
