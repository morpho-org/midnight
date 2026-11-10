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

Permissionlessly refinances a borrower's Midnight debt into a user-selected Morpho Blue market once the Midnight market reaches the configured start timestamp.
It supplies the activated collateral to Blue before, through a callback, borrowing against it on Blue to reward the caller, repay the debt and withdraw the collateral on Midnight.

Users and accounts they authorize on Midnight may enable multiple fallback configurations per Midnight market. 
Users must authorize the contract on both Midnight and Blue. 
Each configuration selects a Blue market, a Midnight market, start timestamp, end timestamp, caller incentive at start, caller incentive at end, and minimum rollable amount, and can later be disabled. 
The caller incentive is a percentage of the debt, is capped at 100% and increases linearly between start and end. 
The minimum rollable amount is the smallest debt a single roll can migrate, and is bypassed by a roll migrating the whole remaining Midnight debt, so a position can always be closed out. 
A roll requires the borrower to have exactly one activated Midnight collateral, matching the collateral token of the configured Blue market.

### `EcrecoverAuthorizer`

Lets an address grant or revoke a Midnight authorization using an EIP-712 signature.
It tracks one nonce per authorizer and rejects expired, replayed, invalid, or unauthorized signatures.

The authorizer must first authorize this contract on Midnight.

### `Log`

An onchain mempool for Midnight.
Its fallback publishes calldata in a `Data` event.
Calldata is limited to 1,000,000 bytes.

### `ReceivableToken`

A claim on the receipts paid to the token contract, meant to be used as collateral on Midnight.

Receipts are paid in the asset directly to the token contract, by plain transfers.
Each token is redeemable for `rate` units of the asset as long as the contract holds them.
The owner sets `rate` to the expected recovery over the total reported amount, minted or not, so receipts beyond the outstanding tokens are still extracted by minting and redeeming.
For example, with 100 reported, 60 minted and 50 received, a rate of 0.5 lets the holders' 60 redeem for 30 and the minter mint the remaining 40 and redeem for 20; computing the rate over the outstanding tokens only would let the holders take the cash due to the unminted capacity.
The token is its own collateral oracle on Midnight markets whose loan token is the asset, so a markdown makes those positions liquidatable and realizes the uncovered debt as bad debt shared by the market's lenders.
Redemptions before the owner updates the rate are first come, first served, like oracle lag before a liquidation.

Any account with an allowance `mint`s tokens, up to `reported` under a report, where `reported` comes from Merkle roots set on the token by its owner (OpenZeppelin `StandardMerkleTree` layout with `(account, reported)` leaves, see `MerkleProofLib` in `receivable-token/libraries`).
The owner allocates the receipts expected by the token between accounts this way, and receipts in excess of the outstanding tokens are extracted the same way, by minting within one's allowance and redeeming.

Each token has an owner, who sets its reports. Whitelisted accounts are Midnight plus every account that has submitted a valid proof under any report, by calling `mint`, possibly with amount 0; the owner can whitelist a non-minter, such as a liquidator or a buyer that wants to keep tokens, by including a leaf with `reported` = 0.
Whitelisting is permanent: leaving an account out of a later report does not remove it. Only whitelisted accounts hold tokens across transactions.
Any other account can still receive tokens, but only transiently: the token credits them in transient storage, calls `onReceivableTokenReceived` on the receiver, and reverts if the receiver still holds tokens when the call returns.
The receiver must redeem them or transfer them to a whitelisted account in that call, so accounts without code cannot receive tokens unless whitelisted.
This keeps liquidations permissionless: Midnight transfers the seized tokens before pulling the repayment, so a liquidator redeems them in the hook and pays with the proceeds.
Midnight is always whitelisted, so nothing can freeze the tokens supplied as collateral on it.

The contract does not interact with Midnight. Minters can sell the tokens, or supply them as collateral on any market listing them and sell debt against them.
The debt is repaid either by the borrower, typically with a repay callback that withdraws and redeems the collateral once the receipts are in, or by a liquidator after maturity who then redeems the seized tokens.
A market can list up to 128 tokens, each with its own LLTV, so lenders diversify across tokens through markets rather than through pooled claims.

### `ReceivableTokenFactory`

Deploys `ReceivableToken`s with `CREATE2` from a caller-provided salt, and records them in `isReceivableToken`.
The factory is deployed with Midnight's address and passes it to every token it deploys, so Midnight is always whitelisted on them.
Anyone creates a token with `createReceivableToken`, picking its owner, asset, name and symbol.

Holders trust a token's owner, who determines who may mint how much and who can hold tokens at all through its reports, and the payers of the receivables.

### `WhitelistEnterGate`

An enter gate that restricts which accounts can increase their credit or debt in a Midnight market.

Each side (credit, debt) has its own whitelist: only whitelisted accounts can enter on that side.
Each side has its own role setter, who grants or revokes the whitelister role on that side.
Whitelisters edit the lists directly with `setIsWhitelisted` or allow to edit the list by EIP-712 signatures used by `setIsWhitelistedWithSig`.
`setIsWhitelistedWithSig` is a no-op instead of a revert when the signed nonce is stale and the account is already set to the signed value.
A side can be made open at deployment, letting any account enter on that side (forever).

### `WhitelistEnterGateFactory`

Deploys a deterministic `WhitelistEnterGate` using `CREATE2` with a salt derived from the caller and a caller-provided pre-salt.
The factory records gates in `isWhitelistEnterGate`.

## Libraries

### `TakeAmountsLib`

Converts target buyer or seller asset amounts into the number of units to take from an offer.
It accounts for the offer price, settlement fee, side, and Midnight's rounding behavior.

### `ConsumableUnitsLib`

Returns the number of units needed to fully consume an offer based on its remaining `maxUnits` or `maxAssets`.
