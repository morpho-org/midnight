# Midnight SQL Queries

Each `.sql` file reconstructs one piece of Midnight's on-chain state from events alone, targeting **Dune Analytics** (Trino SQL with native `uint256`). The queries are self-contained — no off-chain storage is assumed.

## Queries

| File | State variable reconstructed |
|---|---|
| `position.sql` | `position[id][user]` — credit, debt, pendingFee, lastLossFactor, lastAccrual |
| `position_collateral.sql` | `position[id][user].collateral[index]` + collateralBitmap |
| `market_state.sql` | `marketState[id]` — all fields including continuousFeeCredit (recursive CTE) |
| `consumed.sql` | `consumed[user][group]` |
| `is_authorized.sql` | `isAuthorized[authorizer][authorized]` |
| `claimable_trading_fee.sql` | `claimableTradingFee[token]` |
| `default_trading_fee.sql` | `defaultTradingFeeCbp[loanToken][index]` |
| `default_continuous_fee.sql` | `defaultContinuousFee[loanToken]` |
| `roles.sql` | `roleSetter`, `feeSetter`, `feeClaimer`, `tickSpacingSetter` |

Dune table names follow the pattern `midnight.midnight_evt_<eventname>` (all lowercase).

## Testing

The test harness verifies every query against a live Foundry scenario:

1. **`test/SqlScenarioTest.sol`** deploys Midnight, runs a randomised sequence of operations (takes, repays, liquidations, fee claims, …), captures all emitted events via `vm.recordLogs()`, and writes two artefacts:
   - `sql/test/events/<eventname>.json` — one JSON array per event type, used as the SQL input tables
   - `sql/test/expected_state.json` — the actual contract state read at the end, used as ground truth

2. **`test/verify.py`** loads the event JSON files into an in-memory DuckDB instance, executes each `.sql` file against them (adapting Trino-specific syntax on the fly), and asserts that the results match `expected_state.json`.

### Run the tests

```bash
bash sql/test/run.sh
```

This runs the Forge scenario test then the Python verifier in one step. [uv](https://github.com/astral-sh/uv) is required; it installs the pinned Python dependencies automatically.

### Dependencies

Python dependencies are pinned in `sql/test/requirements.txt`:

```
duckdb==1.5.3
pandas==3.0.3
```

The DuckDB version matters: `UHUGEINT` values (used for `uint128` fields such as `lossFactor`) must be returned as exact Python integers, which requires DuckDB ≥ 1.5.

### How the SQL adaptation works

`verify.py` translates Trino SQL to DuckDB SQL on the fly (`adapt_sql`):

- Table references `midnight.midnight_evt_*` → bare table names
- `UINT256 '…'` / `BIGINT '…'` literals → plain integer literals
- `CAST(… AS uint256)` → `CAST(… AS BIGINT)`
- `MAX_BY(x, ROW(block, idx))` → `arg_max(x, block * 1e9 + idx)`
- `WITH` → `WITH RECURSIVE` (DuckDB requires the keyword; Trino infers it)
- The `MAX_U128` sentinel (`2¹²⁸ − 1`) → `…::UHUGEINT` so that CFC arithmetic does not truncate
- The `cfc_state` recursive CTE seed row is rewritten to initialize `cfc` and `prev_lf` as `UHUGEINT` so DuckDB preserves the type throughout the recursion
