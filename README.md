# Midnight

Midnight is a noncustodial fixed-rate lending protocol implemented for the Ethereum Virtual Machine, organized around isolated, immutable, fixed-maturity markets.
Credit and debt behave like zero-coupon obligations, settling at face value at the market’s maturity.
Participants trade by posting or consuming offers that do not lock any capital and source their liquidity at settlement, allowing makers to quote in multiple market at once.
Market creation is permissionless, leaving risk management for upper layers.
Markets can range from single-collateral to portfolio-margined configurations, and optional gates can be used to implement access-control policies.

## Whitepaper

Coming soon...

## Developers

Compilation, testing and formatting are done with [forge](https://book.getfoundry.sh/getting-started/installation).

## Licences

The primary license is the Business Source License 1.1 (BUSL-1.1), see [LICENSE](./LICENSE).
However, all files in the following folders can also be licensed under GPL-2.0-or-later (as indicated in their SPDX headers), see [LICENSE-SECONDARY](./LICENSE-SECONDARY): src/interfaces, src/libraries, test, certora.
