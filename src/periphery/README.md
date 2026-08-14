This folder contains optional helpers for interacting with Midnight.

## Contracts

### `BlueBuyCallback`

A buy callback that uses liquidity supplied on Morpho Blue.

The callback owns the Blue position.
During a Midnight buy, it withdraws the required loan tokens from Blue and approves Midnight to pull them.
The callback data must be the ABI-encoded Blue `MarketParams`.

The owner can grant or revoke permission to manage the callback's Blue position directly with `setAuthorization` or by signature with `setAuthorizationWithSig`.

Anyone authorized to act for the owner on Midnight can trigger this callback through an offer, so the owner should only authorize trusted addresses.

### `BlueBuyCallbackFactory`

Deploys a deterministic `BlueBuyCallback` for an owner using `CREATE2` with a caller-provided salt, so an owner can have several callbacks.
The owner is included in the creation code and combined with the salt, so different owners or salts get different callback addresses.

The factory records callbacks in `callbackOf` and `isBlueBuyCallback`.

### `BlueFallbackRolling`

Permissionlessly refinances a borrower's Midnight debt into a user-selected Morpho Blue market during the configured
rolling period. It supplies the activated collateral to Blue before, through a callback, borrowing against it on Blue
to reward the caller, repay the debt and withdraw the collateral on Midnight.

Users may enable multiple fallback configurations per Midnight market and must authorize the contract on both Midnight
and Blue. Each configuration selects a Blue market, a start and end timestamp for the rolling period, a caller
incentive at each bound, and a minimum rollable amount, and can later be disabled. The caller incentive is a percentage
of the debt, capped at 100%, and interpolates linearly between its two bounds over the rolling period. The minimum
rollable amount is the smallest debt a single roll can migrate, and is bypassed by a roll migrating the whole remaining
Midnight debt, so a position can always be closed out. A roll requires the borrower to have exactly one activated
Midnight collateral, matching the collateral token of the configured Blue market.

A configuration can be set either directly with `setConfig`, or by relaying an EIP-712 signature to
`setConfigWithSig`, which anyone can submit on the user's behalf. Configurations can be set (directly or with a
signature) by the user or by an address authorized for them on Midnight. The signature is bounded by a deadline and
replay-protected by one nonce per user. Configurations set by signature are revoked like any other, with
`setConfig(..., false)`.

### `EcrecoverAuthorizer`

Lets an address grant or revoke a Midnight authorization using an EIP-712 signature.
It tracks one nonce per authorizer and rejects expired, replayed, invalid, or unauthorized signatures.

The authorizer must first authorize this contract on Midnight.

### `Log`

An onchain mempool for Midnight.
Its fallback publishes calldata in a `Data` event.
Calldata is limited to 1,000,000 bytes.

## Libraries

### `TakeAmountsLib`

Converts target buyer or seller asset amounts into the number of units to take from an offer.
It accounts for the offer price, settlement fee, side, and Midnight's rounding behavior.

### `ConsumableUnitsLib`

Returns the number of units needed to fully consume an offer based on its remaining `maxUnits` or `maxAssets`.
