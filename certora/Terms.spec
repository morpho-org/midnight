// SPDX-License-Identifier: GPL-2.0-or-later

/// METHODS ///

methods {
    function withdrawable(bytes32 id) external returns uint256 envfree;
    function balanceOf(address, address) external returns uint256 envfree;
    function id(Terms.Term) external returns bytes32 envfree;

    function _.price() external => NONDET;
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);
}


/// HOOKS ///

persistent ghost mapping(bytes32 => mathint) sumBondOf {
    init_state axiom (forall bytes32 id. sumBondOf[id] == 0);
}
hook Sload uint256 bondOfOwner bondOf[KEY address owner][KEY bytes32 id] {
    require sumBondOf[id] >= to_mathint(bondOfOwner);
}
hook Sstore bondOf[KEY address owner][KEY bytes32 id] uint256 newBond (uint256 oldBond) {
    sumBondOf[id] = sumBondOf[id] - oldBond + newBond;
}

persistent ghost mapping(bytes32 => mathint) sumDebtOf {
    init_state axiom (forall bytes32 id. sumDebtOf[id] == 0);
}
hook Sload uint256 debtOfOwner debtOf[KEY address owner][KEY bytes32 id] {
    require sumDebtOf[id] >= to_mathint(debtOfOwner);
}
hook Sstore debtOf[KEY address owner][KEY bytes32 id] uint256 newDebt (uint256 oldDebt) {
    sumDebtOf[id] = sumDebtOf[id] - oldDebt + newDebt;
}

/// SANITY ///

invariant sanitySumBond(bytes32 id)
    sumBondOf[id] >= 0;

invariant sanitySumDebt(bytes32 id)
    sumDebtOf[id] >= 0;

rule satisfyMatch(env e, calldataarg args) {
    MATCH(e, args);
    satisfy true;
}

/// INVARIANTS ///

strong invariant sums(bytes32 id)
    sumBondOf[id] == sumDebtOf[id] + withdrawable(id);

// invariant balances(TermsHelpers.Term term)
//     balanceOf(term.loanToken, currentContract) >= withdrawable(id(term));
