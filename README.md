# Midnight

Midnight is a noncustodial fixed-rate lending protocol for the Ethereum Virtual Machine, organized around isolated, immutable, fixed-maturity markets.
Credit and debt within each market are fungible and behave like zero-coupon instruments, settling at face value at maturity.
Trading happens through signed executable offers that do not lock capital, so makers can quote across many markets at once, making it viable to support bespoke or long-tail markets.
Markets can range from single-collateral to portfolio-margined configurations, and optional access-control gates let regulated and permissionless markets coexist on the same protocol instance.
Price discovery, risk management, and routing remain outside the protocol core, leaving them to external layers built on top.

## Whitepaper

Coming soon...

## Developers

Compilation, testing and formatting are done with [forge](https://book.getfoundry.sh/getting-started/installation).

## Licences

The primary license is the Business Source License 1.1 (BUSL-1.1), see [LICENSE](./LICENSE).
However, all files in the following folders can also be licensed under GPL-2.0-or-later (as indicated in their SPDX headers), see [LICENSE-SECONDARY](./LICENSE-SECONDARY): src/interfaces, src/libraries, test, certora.
