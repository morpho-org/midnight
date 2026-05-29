# Morpho Midnight

Morpho Midnight is a non-custodial fixed-rate lending protocol implemented for the Ethereum Virtual Machine.
It is organized around isolated, immutable, permissionlessly created markets with fixed-maturity.
Lending and borrowing are implemented through the trading of credit and debt units, whose payoff structure is analogous to that of zero-coupon obligations, settling at the market's maturity.
Participants trade by posting or consuming offers that do not lock capital and source liquidity only at settlement, allowing makers to quote across multiple markets at once.
Markets can range from single to multi-collateral configurations, and gates can be used to implement access-control policies.

## Whitepaper

The protocol is described in detail in the [Midnight Whitepaper](https://morpho.org/whitepapers/midnight-whitepaper.pdf).

## Developers

Compilation, testing and formatting are done with [forge](https://book.getfoundry.sh/getting-started/installation).
If of interest, [BaseTest.sol](https://github.com/morpho-org/midnight/blob/main/test/BaseTest.sol) contains a re-usable testing setup and useful helpers.

The repo contains some formal verification, done with [CVL](https://docs.certora.com/en/latest/docs/cvl/index.html).
[This page](https://github.com/morpho-org/midnight/blob/main/certora/README.md) summarizes the proven properties.

## Licences

The primary license is the Business Source License 1.1 (BUSL-1.1), see [LICENSE](./LICENSE).
However, all files in the following folders can also be licensed under GPL-2.0-or-later (as indicated in their SPDX headers), see [LICENSE-SECONDARY](./LICENSE-SECONDARY): `src/interfaces`, `src/libraries`, `src/ratifiers`, `src/periphery`, `test`, `certora`.
