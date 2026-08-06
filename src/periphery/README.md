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

Permissionlessly refinances a borrower's Midnight debt into a user-selected Morpho Blue market once the Midnight market
reaches the configured start timestamp. It supplies the selected collateral to Blue through a callback, borrows against
it to repay Midnight, and rewards the caller from the additional Blue borrow. Rolls may migrate all debt and collateral
or a proportional partial amount.

The configuration — Midnight market, Blue market, start timestamp, and caller incentive — is immutable, so each
deployment serves exactly one configuration for any number of users. The caller incentive is a percentage of the debt
and is capped at 100%. A roll requires the borrower to have exactly one activated Midnight collateral, matching the
collateral token of the configured Blue market.

Users opt in by authorizing the contract on both Midnight and Blue, and opt out by revoking either authorization. There
is no other configuration to set: because the terms are immutable, the authorization a user grants can only ever result
in that one roll.

### `BlueFallbackRollingFactory`

Deploys a deterministic `BlueFallbackRolling` for a configuration using `CREATE2`, with the hash of the configuration
as the salt, so an instance's address is a pure function of the factory and the configuration and can be computed
before deployment. Deploying an already deployed configuration returns the existing contract.

The factory records deployments in `blueFallbackRollingOf` and `isBlueFallbackRolling`.

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
