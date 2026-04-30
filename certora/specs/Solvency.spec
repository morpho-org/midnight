// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function claimableTradingFee(address token) external returns (uint256) envfree;

    function _.price() external => NONDET;

    // Summarize mulDivUp and mulDivDown by ghost functions. This is for performance of the prover.
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivDown(a, b, denominator);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivUp(a, b, denominator);

    // Summarize toId, this adds no assumption but allows to retrieve the loan token from the obligation id.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);

    // Summaries for complex internals irrelevant to token balance tracking.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
    function UtilsLib.hashOffer(Midnight.Offer memory) internal returns (bytes32) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function _.onRatify(Midnight.Offer, bytes32, bytes) external => NONDET;

    // Hook on callbacks, this adds no assumption: see FlashLiquidateCallback.sol and the summaries below.
    function _.onBuy(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onSell(bytes32, Midnight.Obligation, address, uint256, uint256, bytes) external => NONDET;
    function _.onFlashLoan(address token, uint256 amount, bytes data) external => DISPATCHER(true);
    function _.onLiquidate(bytes32 id, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) external => DISPATCHER(true);
    function _.onRepay(bytes32 id, Midnight.Obligation obligation, uint256 units, address onBehalf, bytes data) external => DISPATCHER(true);
    function FlashLiquidateCallback.startFlashloan(address token, uint256 amount) internal => CVL_flashLoanStart(token, amount);
    function FlashLiquidateCallback.endFlashloan(address token, uint256 amount) internal => CVL_flashLoanEnd(token, amount);

    // Assume ERC20 tokens transfer correctly: no fee taking from sender or receiver, no rebasing, no blacklisting, no transfer limits.
    function _.transfer(address a, uint256 v) external with(env e) => CVL_transferFrom(e, calledContract, e.msg.sender, a, v) expect(bool);
    function _.transferFrom(address src, address a, uint256 v) external with(env e) => CVL_transferFrom(e, calledContract, src, a, v) expect(bool);
}

/// HELPERS ///

// ERC20 summaries.

// Token balances: token => user => balance.
ghost mapping(address => mapping(address => uint256)) tokenBalances;

function CVL_transferFrom(env e, address token, address src, address dest, uint256 value) returns bool {
    if (tokenBalances[token][src] < value || tokenBalances[token][dest] + value >= 2 ^ 256) {
        revert();
    }

    // Non-deterministically set success, which allows to simulate permissions.
    bool success;
    if (success) {
        tokenBalances[token][src] = assert_uint256(tokenBalances[token][src] - value);
        tokenBalances[token][dest] = assert_uint256(tokenBalances[token][dest] + value);
    }
    return success;
}

// UtilsLib summaries.

ghost CVL_mulDivDown(uint256, uint256, uint256) returns uint256;

ghost CVL_mulDivUp(uint256, uint256, uint256) returns uint256;

// IdLib summaries.

// Mapping from obligation id to its loan token.
ghost mapping(bytes32 => address) loantoken;

// Mapping from obligation id and collateral index to the corresponding collateral token.
ghost mapping(bytes32 => mapping(uint128 => address)) collateralToken;

ghost hash(address, uint256, uint256, address) returns bytes32;

function CVL_toId(Midnight.Obligation obligation, uint256 chainId, address midnight) returns bytes32 {
    // Deterministically derive the obligation id.
    bytes32 id = hash(obligation.loanToken, obligation.maturity, chainId, midnight);

    // Assume the obligation id already maps to this loan token.
    // We could also initialize on first use, but then token(0) handling needs extra constraints.
    require(loantoken[id] == obligation.loanToken), "remember the loan token of the obligation";
    require(forall uint128 collateralIndex. collateralIndex < obligation.collateralParams.length => collateralToken[id][collateralIndex] == obligation.collateralParams[collateralIndex].token), "remember the collateral tokens of the obligation";
    return id;
}

// Callbacks summaries.

// Mapping from token to flashloan amount.
// We use persistent ghost to ensure these values are not changed by the callback.
// This is sound as we prove the rule flashLoansPaidBack which ensures that the flashloan amount after the callback is the same as before.
persistent ghost mapping(address => mathint) flashloans {
    init_state axiom (forall address token. flashloans[token] == 0);
}

function CVL_flashLoanStart(address token, uint256 amount) {
    flashloans[token] = flashloans[token] + amount;
}

function CVL_flashLoanEnd(address token, uint256 amount) {
    flashloans[token] = flashloans[token] - amount;
}

// Define collateral sum and withdrawable sum.

definition collateralSum(address token) returns mathint = usum bytes32 id, address owner. collateralMirror[id][owner][token];

ghost mapping(bytes32 => mapping(address => mapping(address => mathint))) collateralMirror {
    init_state axiom (forall bytes32 id. forall address owner. forall address token. collateralMirror[id][owner][token] == 0);
    init_state axiom (forall address token. collateralSum(token) == 0);
}

// Safe require as obligations limit the number of collateralParams.
hook Sload uint128 value position[KEY bytes32 id][KEY address owner].collateral[INDEX uint256 collateralIndex] {
    require value == collateralMirror[id][owner][collateralToken[id][require_uint128(collateralIndex)]], "ghost mirror";
}

// Safe require as obligations limit the number of collateralParams.
hook Sstore position[KEY bytes32 id][KEY address owner].collateral[INDEX uint256 collateralIndex] uint128 newCollateral (uint128 oldCollateral) {
    collateralMirror[id][owner][collateralToken[id][require_uint128(collateralIndex)]] = newCollateral;
}

definition withdrawableSum(address token) returns mathint = usum bytes32 id. withdrawableMirror[id][token];

ghost mapping(bytes32 => mapping(address => mathint)) withdrawableMirror {
    init_state axiom (forall bytes32 id. forall address token. withdrawableMirror[id][token] == 0);
    init_state axiom (forall address token. withdrawableSum(token) == 0);
}

hook Sload uint128 value obligationState[KEY bytes32 id].withdrawable {
    require value == withdrawableMirror[id][loantoken[id]], "ghost mirror";
}

hook Sstore obligationState[KEY bytes32 id].withdrawable uint128 newWithdrawable (uint128 oldWithdrawable) {
    withdrawableMirror[id][loantoken[id]] = newWithdrawable;
}

/// INVARIANTS AND RULES ///

// For any token, the balance of the contract is always greater than or equal to the sum of all collateral, withdrawable, and claimable trading fee amounts for that token minus the flash loaned amount.
// Note: this invariant is strong, so it also holds before each external call.
strong invariant tokenBalanceCorrect(address token)
    tokenBalances[token][currentContract] >= collateralSum(token) + withdrawableSum(token) + claimableTradingFee(token) - flashloans[token]
    {
        preserved with (env e) {
            require e.msg.sender != currentContract, "only external calls";
        }
        preserved take(uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, bytes ratifierData, bytes32 root, bytes32[] proof) with (env e) {
            require e.msg.sender != currentContract, "only external calls";
            require taker != currentContract, "no trading with contract";
            require offer.maker != currentContract, "no trading with contract";
            require offer.callback != currentContract, "midnight reverts on callbacks";
            require takerCallback != currentContract, "midnight reverts on callbacks";
        }
    }

// For any token, the flash loans before and after a call is the same.
// This rule is useful to prove that using persistent ghost for the flashloans mapping is sound.
rule flashLoansPaidBack(method f, address token) {
    env e;
    calldataarg args;
    mathint oldFlashLoan = flashloans[token];
    f(e, args);
    assert flashloans[token] == oldFlashLoan, "flashloan repaid";
}

// For any token, the amount of flash loans after a transaction is 0.
// With tokenBalanceCorrect, this proves that for any token, the balance of the contract is always greater than or equal to the sum of all collateral and withdrawable amounts for that token.
weak invariant flashLoansZero(address token)
    flashloans[token] == 0;
