# The Offer Verification Toolchain

How a maker can know — without trusting the front end, the SDK, their wallet software, or
their hardware wallet's EIP-712 parser — that the offer-tree root they approve commits to
exactly the offers they intend, and nothing else.

## Why this exists: hardware wallets cannot clear-sign the tree

Makers originally clear-signed the full EIP-712 `OfferTree`. Its Merkle representation is
a deeply nested array type (`Offer[2][2]…[2]`), and hardware-wallet firmware must parse
that structure on-device to clear-sign it. Much of the ecosystem cannot:

- **Ledger** (Nano X / S Plus / Flex / Stax): the clear-sign path fails with `0x6a00` on
  larger nested trees; older Ethereum apps (1.17–1.19.3) could produce an *incorrect
  signature* due to a device-side hashing bug.
- **Trezor** (Model T / Safe 3/5/7): hard failure — firmware does not support
  arrays-of-arrays.
- **Original Nano S**: blind signing works but displays nothing meaningful.
- **Custody platforms**: same failure class at different limits (a 64-leaf
  `Offer[2][2][2][2][2][2]` exceeded one vendor's nesting cap of 10).
- **Software wallets** work only because the *host* computes the digest — which is
  exactly the machine we don't want to have to trust.

The failure is structural, not fixable by simplifying an offer field: a routine
single-market chain reaches 32 leaves (six array levels), and multi-market trees reach
256 leaves. Behavior also depends on wallet *software*, not just the device (the same
Ledger succeeded through one wallet's blind-sign path and failed through another's
clear-sign path), and a dapp can neither choose that path nor detect that an EIP-1193
account is hardware-backed.

**The decision shipped:** makers approve the tree *root* instead of signing the tree —
today via an on-chain [`SetterRatifier`](../../src/ratifiers/SetterRatifier.sol)
transaction (hardware-compatible, reversible, one cheap transaction per batch); longer
term via a root-only EIP-712 ratifier that restores off-chain signing without exposing
the nested type to device parsers.

This fixes the device problem but creates a verification problem: **the root is an opaque
32 bytes**. The device can display it faithfully, but nothing on the device tells the
maker what it commits them to. The toolchain in this directory rebuilds that missing
"what am I approving?" verification as an independent, locally runnable pipeline.

## The trust chain

```
offers JSON (human-reviewed intent)
   │  create_certificate.py — independent Python implementation (eth_abi/web3)
   ▼
root + certificate.json (flat leaf/node instruction lists — no nested arrays anywhere)
   │  Checker.sol — replays through the real HashLib via OfferTree.newLeaf/newInternalNode
   ▼
"the root matches under Solidity's own hashing"
   │  Certora proofs — OfferTreeWellFormed.spec + OfferTreeMembership.spec
   ▼
"the root commits to EXACTLY these offers at settlement time"
   │  device screen — compare 32 bytes
   ▼
root approval (SetterRatifier tx today; root-only EIP-712 signature later)
```

Each link removes one party from the trusted base. No single tool is trusted: the Python
and Solidity implementations share no code and must agree, and the formal proofs pin down
what their agreement *means*.

## The maker's workflow, step by step

### Step 0 — Formal verification of the primitives (per release, not per user)

Run by CI: `certoraRun certora/confs/OfferTreeWellFormed.conf` and
`certora/confs/OfferTreeMembership.conf`.

- [`OfferTreeWellFormed.spec`](../specs/OfferTreeWellFormed.spec) proves that any tree
  built through `newLeaf`/`newInternalNode` is well-formed, that a stored leaf re-hashes
  to the real `HashLib.hashOffer` (`hashLeafReproducesHashOffer`), and states the two
  keccak-model axioms the whole chain rests on: leaf/internal-node domain separation
  (`leafHashDisjointFromNodeHash`) and `hashNode` injectivity.
- [`OfferTreeMembership.spec`](../specs/OfferTreeMembership.spec) proves the headline
  (`membershipSoundness`): an offer that passes on-chain `HashLib.isLeaf` against a
  well-formed root **is a leaf of that tree**.

**Guarantee:** a root is a binding commitment to exactly its leaf set — no hidden leaf,
no internal-node-as-leaf forgery, no offer with tweaked fields.
**Still open:** whether *your* root was computed from *your* offers.

### Step 1 — Read the offers

The front end / SDK produces `proofs.json`: the claimed root plus every offer in plain
fields (market, tick, expiry, `maxUnits`, `maxAssets`, `reduceOnly`, …).

**Guarantee:** none — this is the intent step. Everything downstream proves the root
commits to *this file*, so this is the only thing the maker must actually read.

### Step 2 — Independent root recomputation

```
python certora/checker/create_certificate.py proofs.json
```

Recomputes every hash bottom-up with an implementation
([`create_certificate.py`](create_certificate.py), built on `eth_abi`/`web3`) that shares
no code with the front end, and writes `certificate.json`. It hard-fails on root
mismatch, on leaf/node hash collisions, and — via `_check_typehashes`, which re-derives
the three EIP-712 typehashes from their type strings (mirroring
[`HashLibTest.sol`](../../test/HashLibTest.sol)) — on any typehash drift after a struct
change.

**Guarantee:** the claimed root derives from the reviewed offers, independently of the
dapp, the SDK, wallet middleware, and device firmware. This removes exactly the failure
modes observed in the field: a divergent wallet signing path, a device hashing bug, a
tampered front end.
**Still open:** the Python mirror itself could mis-implement Solidity's hashing.

### Step 3 — Canonical replay through Solidity

```
FOUNDRY_PROFILE=checker forge test --match-test testVerifyCertificate
```

[`Checker.sol`](Checker.sol) reads `certificate.json`, rebuilds the tree through
[`OfferTree.newLeaf`/`newInternalNode`](../helpers/OfferTree.sol) — which hash with the
**actual** [`HashLib`](../../src/ratifiers/libraries/HashLib.sol) Midnight executes at
settlement — and asserts the constructed root equals the claimed root.

**Guarantee:** Python and Solidity cross-check each other, and one of them is the
canonical implementation. A bug in either makes the test fail; they cannot "agree
wrongly" unless two independent implementations share the same bug.
**Still open:** whether "these primitives reproduce the root" implies "the root commits
to exactly these offers" — which is precisely what Step 0 proved, over the very
primitives this replay uses.

### Step 4 — Approve on the device

Submit the root approval and compare the 32-byte root on the device screen against the
root printed in steps 2–3.

- **Today:** `SetterRatifier.setIsRootRatified(maker, root, true)` — an ordinary
  transaction, clear-signable on every device including Trezor and the original Nano S,
  and *reversible* (set it back to `false` to unratify the whole batch).
- **Later:** a root-only EIP-712 signature — a flat struct with a single `bytes32`, no
  nesting for any firmware to choke on.

**Guarantee:** what the device displays is byte-for-byte the value the toolchain
verified. The device's inability to parse the tree no longer matters, because the tree
never reaches it.

### Step 5 — Settlement

Takers consume offers by presenting `(offer, leafIndex, proof)`;
[`SetterRatifier.isRatified`](../../src/ratifiers/SetterRatifier.sol) checks
`HashLib.isLeaf` against the approved root.

**Guarantee (Step 0 + Steps 2–4 composed):** *the only offers that can ever settle under
this approval are exactly the ones in the file read in Step 1.*

## The composed guarantee

> If the 32 bytes on my device screen equal the root my local toolchain computed from
> offers I read, then my approval binds me to precisely those offers — nothing else.

The front end, the SDK, the wallet software, and the device's EIP-712 parser are all
outside the trusted base. What remains:

1. **The maker's own machine and toolchain** (Python deps, foundry, solc) — mitigable by
   pinning/vendoring and running air-gapped.
2. **Keccak collision resistance** — stated explicitly as the `nodeHashInjective` /
   `leafHashDisjointFromNodeHash` rules rather than assumed silently.
3. **Deployed bytecode = verified source** — the Certora proofs are about source; check
   the deployed Midnight and ratifier addresses against it once (Etherscan/Sourcify).
4. **Semantic review** — the pipeline proves hash integrity, not that a tick or expiry is
   sensible. Reading `proofs.json` in Step 1 is the one judgment step left in the flow.

## Verifying a signature after the fact (EcrecoverRatifier path)

For makers who *can* sign — note that
[`EcrecoverRatifier`](../../src/ratifiers/EcrecoverRatifier.sol) verifies a digest built
from the root alone:

```
structHash      = keccak256(abi.encode(offerTreeTypeHash(height), root))
domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, chainId, ratifier))
digest          = keccak256("\x19\x01" ‖ domainSeparator ‖ structHash)
```

The nested `Offer[2][2]…` type exists only wallet-side: EIP-712's array hashing
(keccak of concatenated element hash-structs) recursively collapses to the Merkle root,
which is why `HashLib.hashNode` is exactly `keccak256(left ‖ right)`.

A wallet never outputs a root, only `(v, r, s)` — so the after-the-fact check compares
*signers* instead of roots: recompute the root from the maker's own offers (steps 2–3),
rebuild the digest above from that recomputed root, and check
`ecrecover(digest, v, r, s)` equals the maker's address. A signature is valid for one
`(key, digest)` pair, and the digest is a collision-resistant function of the root — so
recovery yielding the maker's address is the cryptographic equivalent of "the signed root
equals the recomputed root". A front end that swapped offers changes the root, hence the
digest, and recovery yields some other address — never the maker's. (This check is not
currently implemented in `create_certificate.py`; the recipe above is what an
implementation must compute.)

## If devices could clear-sign the tree, would this be redundant?

Mostly — and seeing why sharpens what each piece is for. Correct clear signing fuses the
pipeline into one tamper-proof path: the trusted display is Step 1 (the digest is derived
on-device from the same bytes displayed, so host malware cannot decouple "what I read"
from "what gets hashed"), the device's firmware hashing is Step 2 (an independent
implementation isolated from the host), and EIP-712 conformance replaces Step 3 (device
and contract implement the same public standard, and `ecrecover` at settlement only
matches the maker if they agreed). There is no opaque root to compare, so Step 4's ritual
disappears too.

Three things stay load-bearing regardless of signing method:

1. **The contract-side proofs (Step 0).** `membershipSoundness` and domain separation
   protect *settlement* against forged proofs — a taker re-presenting an internal 2-word
   node hash as an "offer" — which has nothing to do with how the signature was made.
2. **Firmware as a single point of failure.** The Ledger 1.17–1.19.3 hashing bug is
   exactly the failure this pipeline's two-independent-implementations design catches and
   a device-only trust chain doesn't. The checker retains value as an audit layer.
3. **Review at scale.** Clear-signing 256 leaves × 15 fields on a device screen is
   theoretical transparency but practical blind-signing-by-fatigue. A host-side JSON you
   can read, diff, and script against is a better review surface for large trees.

## Running it

See the "checker" section of [`../README.md`](../README.md) for the two commands
(`create_certificate.py`, then `FOUNDRY_PROFILE=checker forge test`).

## Internal references

- Ledger investigation: MKT-1179 · SetterRatifier decision: MKT-1239 · custody nesting
  cap: MKT-1552 (Linear, internal).
