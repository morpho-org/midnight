// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // ignore changes done by touchMarket and _updatePosition; the state after these calls is still
    // valid even if they changed the state.
    function touchMarket(Midnight.Market memory) internal returns (bytes32) => NONDET;
    function _updatePosition(Midnight.Market memory, bytes32, address) internal returns (uint128, uint128, uint128) => NONDET;

    // Ignore the transient stores of LIQUIDATION_LOCK via the tExchange method.
    // These are intentionally happen after the external calls.
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;

    // These functions are over-approximated, except for the reverting behavior. We don't look at the reverting behavior in this file.
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256 x, uint256 y, uint256 d) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256 x, uint256 y, uint256 d) internal returns (uint256) => NONDET;
}

// True when at least one slot was written.
persistent ghost bool storageChanged;

// True when at least one CALL is executed after a storage change.
persistent ghost bool hasCallAfterStore;

// True when at least one slot is changed after a CALL is executed after a storage change.
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
    if (storageChanged) {
        hasCallAfterStore = true;
    }
}

// Check that calls are either before the first store nor after the last store (excluding the effects of touchMarket, _updatePosition and tExchange).
rule reentrancySafe(method f, env e, calldataarg data) {
    require(!storageChanged && !hasCallAfterStore && !unsafeCall, "set up the initial ghost state");
    f(e, data);
    assert !unsafeCall;
}
