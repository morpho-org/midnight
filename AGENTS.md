## Review guidelines

### CVL Context

This repo uses the Certora Prover (CVL) to formally verify Solidity contracts.
The primer below describes how CVL actually behaves — read it before reasoning about `.spec` files, because CVL semantics differ in subtle ways from Solidity and from what an LLM might assume by default.

#### Rules, invariants, `satisfy`

- A `rule` passes iff every `assert` holds on every execution path that satisfies all preceding `require`s. A counterexample is a concrete trace (env, args, method choice) that satisfies the `require`s and falsifies an `assert`.
- A rule can be *vacuous*: if the `require`s exclude every path, it passes trivially. Vacuity is silent unless a sanity rule is run. Basic sanity is run by default.
- `satisfy p` is the dual of `assert`: the Prover must find at least one feasible path where `p` holds. A rule with only `satisfy` and no `assert` therefore does not check any universal property.
- CVL has both *weak* and *strong* invariants. A weak invariant is proven by induction over methods: base case checks it after the constructor; inductive step assumes it, runs an arbitrary method `f`, then asserts it again. By default invariants are checked only for `public`/`external` non-`view`/non-`pure` methods. A strong invariant assumes the invariant before any unresolved external calls, havoc the state and assert the invariant after the call. There is no temporal reasoning beyond this.
- A `preserved` block is a code block, that notably allows to inject extra `require`s into the inductive step for one method. Those assumptions are *not* checked by default, but they could be checked in other rules/invariants. Unsound `preserved` is a common source of fake invariant proofs.
- `requireInvariant J` assumes another invariant `J` at the start of the rule/invariant. It's sound only because `J` was itself proven by the same induction scheme.
- A *parametric rule* (one with a `method f` parameter) is expanded into one sub-rule per method in scope. A `filtered { f -> ... }` clause drops methods from that expansion; filtered-out methods are simply not checked.

#### Reverts and path pruning

- By default, a call `f(e, args)` **only explores non-reverting paths**. Reverting executions are silently pruned from the rule. This is a semantic choice, not an optimization.
- `f@withrevert(e, args)` explores both reverting and non-reverting paths. After it, the builtin `lastReverted` is true on the revert branches and false otherwise.
- Without `@withrevert`, `lastReverted` after a call is always `false` (since the revert paths were pruned). Testing `lastReverted` after a plain call is meaningless.
- Non-persistent ghosts are rolled back on revert; persistent ghosts are not.

#### Methods, env, calldataarg

- `env e` captures block number, timestamp, `msg.sender`, `msg.value`, etc. The Prover quantifies over all `env`s consistent with active `require`s.
- `calldataarg args` is an opaque bundle of arguments. You cannot inspect or constrain its fields; it only exists to call a `method f` parametrically.
- `f(e, args)` targets `currentContract` by default. Call other contracts via `other.f(e, args)` where `other` is declared with `using OtherContract as other;`.
- Addresses drawn nondeterministically may coincide with known contracts unless explicitly constrained (`require addr != currentContract`, etc.). The Prover does *not* assume addresses are distinct.
- `envfree` tells the Prover a method doesn't read `env`; such calls omit the `env` argument. The Prover statically checks this.

#### Ghosts, hooks, havoc

- A ghost is an SMT variable (possibly a function `uint → uint`, etc.), not contract state. It exists only in the spec and can be updated by hooks or CVL assignments.
- On an *unresolved* external call, the Prover havocs all non-persistent ghosts (assumes they take any value consistent with their axioms). `persistent ghost` declarations survive havoc.
- Hooks fire on EVM-level events: `Sload`, `Sstore`, `CALL`, `REVERT`, etc. They match by storage slot / selector / opcode. Signature or layout drift silently disables a hook — it does not error. Hooks are not triggered by CVL code, including CVL access to Solidity storage, and hooks are not recursive.
- Inside an `Sstore` hook, the bound names conventionally written as old/new values refer to the pre-write and post-write values at that slot.
- A two-state ghost function can be referenced as `g@old` / `g@new` inside `havoc g assuming ...`, letting you specify how the ghost changes across a havoc (e.g. `havoc g assuming g@new(x) == g@old(x) + 1`).
- `axiom P` constrains the ghost in every state the Prover considers — adding an unsatisfiable axiom makes every rule vacuously pass. `init_state axiom P` only constrains the ghost in the base case of invariant induction, which is almost always what you want for "starts at zero"-style facts.
- Ghost axioms may refer only to the ghost itself and quantified variables — not to Solidity or CVL functions.

#### Summaries and dispatch

- The `methods { ... }` block declares how external calls are resolved. Exact-signature entries beat wildcard entries (`function _.foo() ...`).
- `AUTO` (the default for unresolved calls): view/pure methods are summarized as NONDET, other external calls are summarized as HAVOC_ECF (see below).
- `DISPATCHER(true)` / `DISPATCHER(false)`: on an unresolved interface call, the Prover considers every known contract with that selector. `true` is *optimistic* (only known impls are considered, assumed to be the full set); `false` is pessimistic (assumes an unknown impl could also exist). DISPATCHER does not apply to library calls.
- `HAVOC_ALL` erases all contract state plus the return value — the maximally conservative summary. `HAVOC_ECF` (externally-controlled footprint) only havocs state that non-reentrant external callees could touch.
- `NONDET` returns an unconstrained value and does not touch storage. For stateful methods it is unsound unless combined with a havoc.
- A CVL function summary `=> cvlFn(args)` substitutes the CVL function body for the call. The Prover never looks at the Solidity body, so the summary must match the contract's semantics or proofs are unsound.
- `DELETE` (e.g. `HAVOC_ALL DELETE`) additionally removes the callee's code from the scene, preventing path explosion from modeling its body.

#### Types and casts

- `mathint` is unbounded signed integer; arithmetic never overflows. `uint256` / `int256` wrap modulo 2^n. Mixing them requires an explicit cast.
- `to_mathint(x)` widens a machine int to `mathint` (always safe). `assert_uint256(m)` converts back and fails the current rule if `m` doesn't fit. `require_uint256(m)` converts back and *assumes* it fits (which can introduce vacuity if it never does). Arithmetic operations in CVL automatically convert the result to mathint, so in most cases `to_mathint` is not needed and redundant.
- `storage` is a first-class type. `storage s = lastStorage;` snapshots the full state; `f(e, args) at s` re-executes from that snapshot. `s1 == s2` compares every slot of every contract in scope — it's correct but expensive.
- Direct field access on storage (`currentContract.x.y`) works for primitive/static-layout fields but not for dynamic arrays, `bytes`, or `string`.

#### Quantifiers

- `forall type v. e` / `exists type v. e` are first-class in CVL. The solver reasons about them via standard SMT quantifier handling; nested quantifiers and quantifiers over large domains drive solver blow-up.
- Quantified expressions cannot call contract functions — they can only reference ghosts, storage, and CVL-pure expressions.

#### Multi-contract setup

- `currentContract` is the main verified contract (set in the `.conf`). Other contracts are linked by `using Foo as foo;`. By default, invariants and parametric rules range over methods of all contracts in the scene; `--parametric_contracts` narrows that set.
- Inside hooks, `executingContract` can differ from `currentContract` when a hook fires during a sub-call.

### What to focus on

Flag notably these issues:
- Typos, broken links, and inconsistent formatting
- State not being fully reconstructible through events
- Outdated documentation
- Inconsistent naming
- Issues in tests
- Major gas optimizations
- Readability issues

Don't flag breaking changes, the code is not in production and will be immutable.
Flag all issues, including those that were not introduced in this commit or pull request.
Spend some time on P2 and P3 issues too.

### Output

Try to be as concise as possible in your output.
When relevant, include in your comment directly the fix you would apply (as a suggestion markdown block).
