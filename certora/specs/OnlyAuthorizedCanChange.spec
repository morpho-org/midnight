// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function balanceOf(bytes32 id, address user) external returns (int256) envfree;
    function debtOf(bytes32 id, address user) external returns (uint256) envfree;
    function isAuthorized(address authorizer, address authorized) external returns (bool) envfree;

    // Summarize internal functions that use opcodes causing HAVOC (CREATE2, low-level calls).
    function IdLib.storeInCode(Midnight.Obligation memory) internal returns (address) => NONDET;
    function SafeTransferLib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeTransferLib.safeTransferFrom(address, address, address, uint256) internal => NONDET;

    // Summarize complex internals irrelevant to balance tracking.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;

    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    function _.price() external => CVL_price(calledContract) expect(uint256);

    // Assume no reentrancy: callbacks do not re-enter Midnight.
    function _.onBuy(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onSell(Midnight.Obligation, address, uint256, uint256, uint256, bytes) external => NONDET;
    function _.onFlashLoan(address, uint256, bytes) external => NONDET;

    function signer(bytes32, Midnight.Signature memory) internal returns (address) => CVL_signer();
}

/// HELPERS ///

ghost CVL_price(address) returns uint256;

ghost mapping(address => bool) signed {
    init_state axiom forall address a. signed[a] == false;
}

function CVL_signer() returns address {
    address result;
    signed[result] = true;
    return result;
}

/// BALANCE CHANGE RULES ///

/// An unauthorized caller cannot change a user's balance except via slash.
/// Assumes no reentrancy: callbacks (onBuy, onSell) and token transfers are not modeled as re-entering Midnight, so re-entrant balance changes are not covered.
rule onlyAuthorizedCanChangeBalanceExceptSlash(env e, method f, calldataarg args, bytes32 id, address user) filtered { f -> f.selector != sig:slash(bytes32, address).selector } {
    bool userIsAuthorized = user == e.msg.sender || isAuthorized(user, e.msg.sender);
    Midnight.Obligation obligation = toObligation(e, id);
    bool userIsUnHealthy = !isHealthy(e, obligation, id, user);
    bool isPastMaturity = e.block.timestamp > obligation.maturity;

    int256 balanceBefore = balanceOf(id, user);
    f(e, args);
    int256 balanceAfter = balanceOf(id, user);

    assert balanceAfter == balanceBefore || userIsAuthorized || signed[user] || userIsUnHealthy || isPastMaturity;
}
