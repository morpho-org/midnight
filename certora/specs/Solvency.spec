// SPDX-License-Identifier: GPL-2.0-or-later

using ERC20 as standardToken;
using ERC20NoRevert as noRevertToken;
using ERC20USDT as usdtToken;
using ERC20RevertToZero as revertToZeroToken;
using ERC20NoReturn as noReturnToken;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.price() external => NONDET;

    // Summarize mulDivUp and mulDivDown by ghost functions. This is for performance of the prover.
    function UtilsLib.mulDivDown(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivDown(a, b, denominator);
    function UtilsLib.mulDivUp(uint256 a, uint256 b, uint256 denominator) internal returns (uint256) => CVL_mulDivUp(a, b, denominator);

    // Summarize toId, this adds no assumption but allows to retrieve the loan token from the obligation id.
    function IdLib.toId(Midnight.Obligation memory obligation, uint256 chainId, address midnight) internal returns (bytes32) => CVL_toId(obligation, chainId, midnight);

    // Summaries for complex internals irrelevant to token balance tracking.
    function UtilsLib.isLeaf(bytes32, bytes32, bytes32[] memory) internal returns (bool) => NONDET;
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;

    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function TickLib.wExp(int256) internal returns (uint256) => NONDET;
    function isHealthy(Midnight.Obligation memory, bytes32, address) internal returns (bool) => NONDET;
    function tradingFee(bytes32, uint256) internal returns (uint256) => NONDET;

    // Hook on callbacks, this adds no assumption: see FlashLiquidateCallback.sol and the summaries below.
    function _.onFlashLoan(address token, uint256 amount, bytes data) external => DISPATCHER(true);
    function _.onLiquidate(bytes32 obligationId, Midnight.Obligation obligation, uint256 collateralIndex, uint256 seizedAssets, uint256 repaidUnits, address borrower, bytes data) external => DISPATCHER(true);
    function FlashLiquidateCallback.startFlashloan(address token, uint256 amount) internal => CVL_flashLoanStart(token, amount);
    function FlashLiquidateCallback.endFlashloan(address token, uint256 amount) internal => CVL_flashLoanEnd(token, amount);

    function standardToken.balanceOf(address) external returns (uint256) envfree;
    function noRevertToken.balanceOf(address) external returns (uint256) envfree;
    function usdtToken.balanceOf(address) external returns (uint256) envfree;
    function revertToZeroToken.balanceOf(address) external returns (uint256) envfree;
    function noReturnToken.balanceOf(address) external returns (uint256) envfree;

    // Dispatch ERC20 calls through the concrete weird token implementations in the scene.
    function _.transfer(address a, uint256 v) external => DISPATCH(optimistic=true)[
        ERC20.transfer(address,uint256),
        ERC20NoRevert.transfer(address,uint256),
        ERC20USDT.transfer(address,uint256),
        ERC20RevertToZero.transfer(address,uint256),
        ERC20NoReturn.transfer(address,uint256)
    ];
    function _.transferFrom(address src, address a, uint256 v) external => DISPATCH(optimistic=true)[
        ERC20.transferFrom(address,address,uint256),
        ERC20NoRevert.transferFrom(address,address,uint256),
        ERC20USDT.transferFrom(address,address,uint256),
        ERC20RevertToZero.transferFrom(address,address,uint256),
        ERC20NoReturn.transferFrom(address,address,uint256)
    ];
}

/// HELPERS ///

// ERC20 helpers.

definition isSupportedToken(address token) returns bool =
    token == standardToken
    || token == noRevertToken
    || token == usdtToken
    || token == revertToZeroToken
    || token == noReturnToken;

function tokenBalance(address token) returns mathint {
    if (token == standardToken) return standardToken.balanceOf(currentContract);
    if (token == noRevertToken) return noRevertToken.balanceOf(currentContract);
    if (token == usdtToken) return usdtToken.balanceOf(currentContract);
    if (token == revertToZeroToken) return revertToZeroToken.balanceOf(currentContract);
    if (token == noReturnToken) return noReturnToken.balanceOf(currentContract);
    return 0;
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

    // Restrict obligations to the token implementations in the scene so token calls dispatch concretely.
    require(isSupportedToken(obligation.loanToken), "supported loan token");
    require(
        forall uint128 collateralIndex.
            collateralIndex < obligation.collaterals.length => isSupportedToken(obligation.collaterals[collateralIndex].token),
        "supported collateral tokens"
    );

    // Assume the obligation id already maps to this loan token.
    // We could also initialize on first use, but then token(0) handling needs extra constraints.
    require(loantoken[id] == obligation.loanToken), "remember the loan token of the obligation";
    require(forall uint128 collateralIndex. collateralIndex < obligation.collaterals.length => collateralToken[id][collateralIndex] == obligation.collaterals[collateralIndex].token), "remember the collateral tokens of the obligation";
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

definition collateralSum(address token) returns mathint = usum bytes32 id, address owner. collateralOfMirror[id][owner][token];

ghost mapping(bytes32 => mapping(address => mapping(address => mathint))) collateralOfMirror {
    init_state axiom (forall bytes32 id. forall address owner. forall address token. collateralOfMirror[id][owner][token] == 0);
    init_state axiom (forall address token. collateralSum(token) == 0);
}

// Safe require as obligations limit the number of collaterals.
hook Sload uint128 value position[KEY bytes32 id][KEY address owner].collateral[INDEX uint256 collateralIndex] {
    require value == collateralOfMirror[id][owner][collateralToken[id][require_uint128(collateralIndex)]], "ghost mirror";
}

// Safe require as obligations limit the number of collaterals.
hook Sstore position[KEY bytes32 id][KEY address owner].collateral[INDEX uint256 collateralIndex] uint128 newCollateral (uint128 oldCollateral) {
    collateralOfMirror[id][owner][collateralToken[id][require_uint128(collateralIndex)]] = newCollateral;
}

definition withdrawableSum(address token) returns mathint = usum bytes32 id. withdrawableMirror[id][token];

ghost mapping(bytes32 => mapping(address => mathint)) withdrawableMirror {
    init_state axiom (forall bytes32 id. forall address token. withdrawableMirror[id][token] == 0);
    init_state axiom (forall address token. withdrawableSum(token) == 0);
}

hook Sload uint256 value obligationState[KEY bytes32 id].withdrawable {
    require value == withdrawableMirror[id][loantoken[id]], "ghost mirror";
}

hook Sstore obligationState[KEY bytes32 id].withdrawable uint256 newWithdrawable (uint256 oldWithdrawable) {
    withdrawableMirror[id][loantoken[id]] = newWithdrawable;
}

/// INVARIANTS AND RULES ///

// For any token, the balance of the contract is always greater than or equal to the sum of all collateral and withdrawable amounts for that token minus the flash loaned amount.
// Note: this invariant is strong, so it also holds before each external call.
strong invariant tokenBalanceCorrect(address token)
    tokenBalance(token) >= collateralSum(token) + withdrawableSum(token) - flashloans[token]
    {
        preserved with (env e) {
            require e.msg.sender != currentContract, "only external calls";
        }
        preserved take(uint256 units, address taker, address takerCallback, bytes takerCallbackData, address receiverIfTakerIsSeller, Midnight.Offer offer, Midnight.Signature signature, bytes32 root, bytes32[] proof) with (env e) {
            require taker != currentContract, "no trading with contract";
            require offer.maker != currentContract, "no trading with contract";
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
