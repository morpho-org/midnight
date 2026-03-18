// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => NONDET;

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.countBits(uint128) internal returns (uint256) => NONDET;

    function IdLib.toId(Midnight.Obligation memory, uint256, address) internal returns (bytes32) => NONDET;

    function accrueContinuousFee(bytes32 id, address borrower, uint256 maturity) internal => summaryAccrueContinuousFee(id, borrower);
}

/// GHOSTS ///

/// Whether accrueContinuousFee was called for (id, user) in this transaction.
persistent ghost mapping(bytes32 => mapping(address => bool)) accrued;

/// Whether debt was stored before accrueContinuousFee was called for (id, user).
persistent ghost mapping(bytes32 => mapping(address => bool)) debtStoredBeforeAccrual;

/// Whether debt was loaded before accrueContinuousFee was called for (id, user).
persistent ghost mapping(bytes32 => mapping(address => bool)) debtLoadedBeforeAccrual;

/// SUMMARY ///

/// Summary for accrueContinuousFee: just sets the accrued ghost flag.
/// The original function body is replaced, so its internal debt reads/writes do not fire hooks.
function summaryAccrueContinuousFee(bytes32 id, address borrower) {
    accrued[id][borrower] = true;
}

/// HOOKS ///

hook Sstore position[KEY bytes32 id][KEY address user].debt uint128 newVal (uint128 oldVal) {
    if (!accrued[id][user] && (oldVal != 0 || newVal != 0)) {
        debtStoredBeforeAccrual[id][user] = true;
    }
}

hook Sload uint128 val position[KEY bytes32 id][KEY address user].debt {
    if (!accrued[id][user] && val != 0) {
        debtLoadedBeforeAccrual[id][user] = true;
    }
}

/// RULES ///

/// Check that debt is never stored before accrueContinuousFee is called.
/// The SSTOREs of accrueContinuousFee are ignored.
rule debtNotStoredBeforeAccrual(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> !f.isView } {
    require !accrued[id][user], "initialize the ghost variable";
    require !debtStoredBeforeAccrual[id][user], "initialize the ghost variable";

    f(e, args);

    assert !debtStoredBeforeAccrual[id][user], "debt was stored before accrueContinuousFee was called";
}

/// Check that debt is never loaded before accrueContinuousFee is called.
/// The SLOADs of accrueContinuousFee are ignored.
rule debtNotLoadedBeforeAccrual(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:isHealthy(Midnight.Obligation memory, bytes32, address).selector && f.selector != sig:debtOf(bytes32, address).selector } {
    require !accrued[id][user], "initialize the ghost variable";
    require !debtLoadedBeforeAccrual[id][user], "initialize the ghost variable";

    f(e, args);

    assert !debtLoadedBeforeAccrual[id][user], "debt was loaded before accrueContinuousFee was called";
}
