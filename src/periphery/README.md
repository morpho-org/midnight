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

The factory records callbacks in `callbackOf` and `isBlueCallback`.

### `BlueFallbackRolling`

Permissionlessly refinances a borrower's Midnight debt into one or more user-selected Morpho Blue markets once the
Midnight market reaches the configured start timestamp. A roll processes one leg per activated Midnight collateral to
migrate, each leg supplying that collateral to its own Blue market through a callback, borrowing against it to repay
Midnight, and rewarding the caller from the additional Blue borrow. Legs may migrate all debt and collateral or a
proportional partial amount, and a single roll can target any subset of the borrower's activated collaterals.

Users may enable multiple fallback configurations per Midnight market and must authorize the contract on both Midnight
and Blue. Each configuration selects a Blue market, start timestamp, and caller incentive, and can later be disabled.
The caller incentive is a percentage of the debt and is capped at 100%; the start timestamp and incentive are shared
across every leg of a given roll. Each leg's target collateral must be activated on the Midnight position, must not
repeat another leg's collateral, and must match the collateral token of its configured Blue market.

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
