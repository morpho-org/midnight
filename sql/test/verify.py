#!/usr/bin/env python3
"""
Verifies Midnight SQL queries against exported events and expected state.

Usage (from repo root):
    python3 sql/test/verify.py

Prerequisites:
    pip install duckdb pandas
    forge test --match-test testGenerateScenario -vv  (run first)
"""

import json
import os
import re
import sys

import duckdb
import pandas as pd

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EVENTS_DIR = os.path.join(REPO_ROOT, "sql", "test", "events")
EXPECTED_FILE = os.path.join(REPO_ROOT, "sql", "test", "expected_state.json")
SQL_DIR = os.path.join(REPO_ROOT, "sql")


# ── SQL adaptation (Dune/Trino → DuckDB) ─────────────────────────────────────

def adapt_sql(sql: str) -> str:
    sql = sql.replace("midnight.midnight_evt_", "midnight_evt_")
    # DuckDB requires WITH RECURSIVE for recursive CTEs (Trino infers it automatically)
    sql = re.sub(r"\bWITH\b", "WITH RECURSIVE", sql, count=1)
    # to_unixtime must come before the CAST regex (the CAST may wrap it)
    sql = sql.replace("to_unixtime(evt_block_time)", "evt_block_time")
    sql = re.sub(r"UINT256 '(\d+)'", r"\1", sql)
    sql = re.sub(r"BIGINT '(\d+)'", r"\1", sql)
    sql = re.sub(
        r"(?i)\bCAST\(([^)]+)\s+AS\s+uint256\)",
        lambda m: f"CAST({m.group(1)} AS BIGINT)",
        sql,
    )
    sql = re.sub(
        r"MAX_BY\(([\s\S]+?),\s*ROW\(([\s\S]+?),\s*([\s\S]+?)\)\)",
        lambda m: (
            f"arg_max({m.group(1).strip()}, "
            f"CAST({m.group(2).strip()} AS BIGINT) * 1000000000 + "
            f"CAST({m.group(3).strip()} AS BIGINT))"
        ),
        sql,
    )
    return sql


# ── Event table schemas ───────────────────────────────────────────────────────
# (table_name -> (filename, int_cols, bool_cols))

# (table_name -> (filename, int_cols, bool_cols, str_cols))
# str_cols is required to correctly build empty tables when the JSON array is [].
EVENT_SCHEMAS: dict[str, tuple[str, list[str], list[str], list[str]]] = {
    "midnight_evt_take": (
        "take.json",
        ["buyerassets", "sellerassets", "units", "consumed",
         "buyerpendingfeeincrease", "sellerpendingfeedecrease",
         "evt_block_number", "evt_index"],
        ["offerisbuy"],
        ["id_", "maker", "taker", "group"],
    ),
    "midnight_evt_updateposition": (
        "updateposition.json",
        ["creditdecrease", "pendingfeedecrease", "accruedfee",
         "evt_block_number", "evt_index", "evt_block_time"],
        [],
        ["id_", "user"],
    ),
    "midnight_evt_withdraw": (
        "withdraw.json",
        ["units", "pendingfeedecrease", "evt_block_number", "evt_index"],
        [],
        ["id_", "onbehalf", "receiver"],
    ),
    "midnight_evt_repay": (
        "repay.json",
        ["units", "evt_block_number", "evt_index"],
        [],
        ["id_", "onbehalf"],
    ),
    "midnight_evt_supplycollateral": (
        "supplycollateral.json",
        ["assets", "evt_block_number", "evt_index"],
        [],
        ["id_", "collateral", "onbehalf"],
    ),
    "midnight_evt_withdrawcollateral": (
        "withdrawcollateral.json",
        ["assets", "evt_block_number", "evt_index"],
        [],
        ["id_", "collateral", "onbehalf"],
    ),
    "midnight_evt_marketcreated": (
        "marketcreated.json",
        ["market_maturity",
         "market_settlementfeecbp0", "market_settlementfeecbp1", "market_settlementfeecbp2",
         "market_settlementfeecbp3", "market_settlementfeecbp4", "market_settlementfeecbp5",
         "market_settlementfeecbp6", "market_continuousfee",
         "evt_block_number", "evt_index"],
        [],
        ["id_", "market_loantoken"],
    ),
    "midnight_evt_setconsumed": (
        "setconsumed.json",
        ["amount", "evt_block_number", "evt_index"],
        [],
        ["onbehalf", "group"],
    ),
    "midnight_evt_setisauthorized": (
        "setisauthorized.json",
        ["evt_block_number", "evt_index"],
        ["newisauthorized"],
        ["onbehalf", "authorized"],
    ),
    "midnight_evt_setdefaultsettlementfee": (
        "setdefaultsettlementfee.json",
        ["index", "newsettlementfee", "evt_block_number", "evt_index"],
        [],
        ["loantoken"],
    ),
    "midnight_evt_setmarketsettlementfee": (
        "setmarketsettlementfee.json",
        ["index", "newsettlementfee", "evt_block_number", "evt_index"],
        [],
        ["id_"],
    ),
    "midnight_evt_setmarketcontinuousfee": (
        "setmarketcontinuousfee.json",
        ["newcontinuousfee", "evt_block_number", "evt_index"],
        [],
        ["id_"],
    ),
    "midnight_evt_claimsettlementfee": (
        "claimsettlementfee.json",
        ["amount", "evt_block_number", "evt_index"],
        [],
        ["token"],
    ),
    "midnight_evt_claimcontinuousfee": (
        "claimcontinuousfee.json",
        ["amount", "evt_block_number", "evt_index"],
        [],
        ["id_"],
    ),
    "midnight_evt_constructor": (
        "constructor.json",
        ["evt_block_number", "evt_index"],
        [],
        ["rolesetter"],
    ),
    "midnight_evt_setfeesetter": (
        "setfeesetter.json",
        ["evt_block_number", "evt_index"],
        [],
        ["feesetter"],
    ),
    "midnight_evt_setfeeclaimer": (
        "setfeeclaimer.json",
        ["evt_block_number", "evt_index"],
        [],
        ["feeclaimer"],
    ),
    "midnight_evt_settickspacingsetter": (
        "settickspacingsetter.json",
        ["evt_block_number", "evt_index"],
        [],
        ["tickspacingsetter"],
    ),
    "midnight_evt_setdefaultcontinuousfee": (
        "setdefaultcontinuousfee.json",
        ["newcontinuousfee", "evt_block_number", "evt_index"],
        [],
        ["loantoken"],
    ),
    "midnight_evt_liquidate": (
        "liquidate.json",
        ["seizedassets", "repaidunits", "baddebt",
         "evt_block_number", "evt_index"],
        ["postmaturitymode"],
        ["id_", "collateral", "borrower"],
        ["latestlossfactor", "latestcontinuousfeecredit"],  # uint128 — stored as UHUGEINT to hold values up to MAX_U128
    ),
}

# Tables referenced by some SQL files but not emitted in our test scenario
EMPTY_TABLE_SCHEMAS: dict[str, str] = {
    "midnight_evt_setrolesetter": (
        "rolesetter VARCHAR, evt_block_number BIGINT, evt_index BIGINT"
    ),
    "midnight_evt_setmarkettickspacing": (
        "id_ VARCHAR, newtickspacing BIGINT, evt_block_number BIGINT, evt_index BIGINT"
    ),
}


def load_events(conn: duckdb.DuckDBPyConnection) -> None:
    for table_name, schema_tuple in EVENT_SCHEMAS.items():
        if len(schema_tuple) == 5:
            filename, int_cols, bool_cols, str_cols, uhugeint_cols = schema_tuple
        else:
            filename, int_cols, bool_cols, str_cols = schema_tuple
            uhugeint_cols = []

        filepath = os.path.join(EVENTS_DIR, filename)
        with open(filepath) as f:
            rows = json.load(f)

        all_cols = str_cols + int_cols + uhugeint_cols + bool_cols

        if not rows or uhugeint_cols:
            # Use explicit DDL for empty tables or tables with UHUGEINT columns.
            # Pandas type inference cannot reliably represent uint128 values.
            col_defs = ", ".join(
                f"{c} UHUGEINT" if c in uhugeint_cols else
                f"{c} BIGINT" if c in int_cols else
                f"{c} BOOLEAN" if c in bool_cols else
                f"{c} VARCHAR"
                for c in (all_cols or ["dummy"])
            )
            conn.execute(f"CREATE TABLE {table_name} ({col_defs})")
            if rows:
                placeholders = ", ".join("?" * len(all_cols))
                data = []
                for row in rows:
                    values = []
                    for c in all_cols:
                        v = row.get(c)
                        if c in uhugeint_cols or c in int_cols:
                            values.append(int(v) if v is not None else 0)
                        elif c in bool_cols:
                            values.append(bool(v) if v is not None else False)
                        else:
                            values.append(str(v).lower() if v is not None else "")
                    data.append(values)
                conn.executemany(f"INSERT INTO {table_name} VALUES ({placeholders})", data)
            continue

        # Pandas path — no UHUGEINT columns, table has data
        converted = []
        for row in rows:
            new_row: dict = {}
            for k, v in row.items():
                if k in int_cols:
                    new_row[k] = int(v) if v is not None else 0
                elif k in bool_cols:
                    new_row[k] = bool(v)
                else:
                    new_row[k] = str(v).lower() if v is not None else ""
            converted.append(new_row)

        df = pd.DataFrame(converted)
        conn.register(f"_df_{table_name}", df)
        conn.execute(f"CREATE TABLE {table_name} AS SELECT * FROM _df_{table_name}")

    for table_name, col_defs in EMPTY_TABLE_SCHEMAS.items():
        conn.execute(f"CREATE TABLE {table_name} ({col_defs})")


def run_sql(conn: duckdb.DuckDBPyConnection, sql_path: str) -> pd.DataFrame:
    with open(sql_path) as f:
        raw = f.read()
    adapted = adapt_sql(raw)
    try:
        result = conn.execute(adapted)
        columns = [desc[0] for desc in result.description]
        rows = result.fetchall()
        return pd.DataFrame(rows, columns=columns)
    except Exception as exc:
        print(f"ERROR in {os.path.basename(sql_path)}:")
        print(exc)
        raise


def verify_all() -> None:
    with open(EXPECTED_FILE) as f:
        exp = json.load(f)

    conn = duckdb.connect()
    load_events(conn)

    failures: list[str] = []

    def fail(msg: str) -> None:
        failures.append(f"  {msg}")

    def check_int(label: str, actual, expected_val) -> None:
        try:
            a, e = int(actual), int(expected_val)
            if a != e:
                fail(f"{label}: got {a}, expected {e}")
        except Exception as exc:
            fail(f"{label}: comparison error – {exc}")

    def check_str(label: str, actual, expected_val) -> None:
        a = str(actual).lower().strip()
        e = str(expected_val).lower().strip()
        if a != e:
            fail(f"{label}: got {a!r}, expected {e!r}")

    # ── position.sql ─────────────────────────────────────────────────────────
    print("Verifying position.sql …")
    df_pos = run_sql(conn, os.path.join(SQL_DIR, "position.sql"))
    df_pos["user"] = df_pos["user"].str.lower()
    for user_key, addr_key in [
        ("position_lender",         "lender_addr"),
        ("position_borrower",       "borrower_addr"),
        ("position_other_borrower", "other_borrower_addr"),
    ]:
        addr = exp[addr_key].lower()
        row = df_pos[df_pos["user"] == addr]
        if row.empty:
            fail(f"position.sql: no row for {user_key}")
            continue
        r = row.iloc[0]
        pos = exp[user_key]
        for field in ["credit", "debt", "pending_fee", "last_loss_factor", "last_accrual"]:
            check_int(f"{user_key}.{field}", r[field], pos[field])

    # ── market_state.sql ──────────────────────────────────────────────────────
    print("Verifying market_state.sql …")
    df_ms = run_sql(conn, os.path.join(SQL_DIR, "market_state.sql"))
    if df_ms.empty:
        fail("market_state.sql: no rows")
    else:
        r = df_ms.iloc[0]
        ms = exp["market_state"]
        for field in [
            "total_units", "loss_factor", "withdrawable", "continuous_fee_credit",
            "settlement_fee_cbp_0", "settlement_fee_cbp_1", "settlement_fee_cbp_2",
            "settlement_fee_cbp_3", "settlement_fee_cbp_4", "settlement_fee_cbp_5",
            "settlement_fee_cbp_6", "continuous_fee", "tick_spacing",
        ]:
            check_int(f"market_state.{field}", r[field], ms[field])

    # ── consumed.sql ──────────────────────────────────────────────────────────
    print("Verifying consumed.sql …")
    df_con = run_sql(conn, os.path.join(SQL_DIR, "consumed.sql"))
    df_con["user"] = df_con["user"].str.lower()
    df_con["group"] = df_con["group"].str.lower()
    borrower_addr = exp["borrower_addr"].lower()
    group_a = exp["group_a"].lower()
    row = df_con[
        (df_con["user"] == borrower_addr) & (df_con["group"] == group_a)
    ]
    if row.empty:
        fail("consumed.sql: no row for borrower+GROUP_A")
    else:
        check_int(
            "consumed.borrower_group_a",
            row.iloc[0]["amount"],
            exp["consumed_borrower_group_a"],
        )

    # ── is_authorized.sql ─────────────────────────────────────────────────────
    print("Verifying is_authorized.sql …")
    df_auth = run_sql(conn, os.path.join(SQL_DIR, "is_authorized.sql"))
    df_auth["authorizer"] = df_auth["authorizer"].str.lower()
    df_auth["authorized"] = df_auth["authorized"].str.lower()
    lender_addr = exp["lender_addr"].lower()
    other_lender_addr = exp["other_lender_addr"].lower()
    row = df_auth[
        (df_auth["authorizer"] == lender_addr)
        & (df_auth["authorized"] == other_lender_addr)
    ]
    exp_val = exp["is_authorized_lender_other_lender"]
    if row.empty:
        if exp_val:
            fail("is_authorized.sql: no row for lender→otherLender (expected true)")
    else:
        check_str(
            "is_authorized.lender_other_lender",
            row.iloc[0]["is_authorized"],
            str(exp_val).lower(),
        )

    # ── claimable_settlement_fee.sql ─────────────────────────────────────────────
    print("Verifying claimable_settlement_fee.sql …")
    df_ctf = run_sql(conn, os.path.join(SQL_DIR, "claimable_settlement_fee.sql"))
    loan_token = exp["loan_token_addr"].lower()
    if not df_ctf.empty:
        df_ctf["token"] = df_ctf["token"].str.lower()
    row = df_ctf[df_ctf["token"] == loan_token] if not df_ctf.empty else df_ctf
    if row.empty:
        check_int("claimable_settlement_fee", 0, exp["claimable_settlement_fee"])
    else:
        check_int(
            "claimable_settlement_fee",
            row.iloc[0]["claimable_settlement_fee"],
            exp["claimable_settlement_fee"],
        )

    # ── default_settlement_fee.sql ───────────────────────────────────────────────
    print("Verifying default_settlement_fee.sql …")
    df_dtf = run_sql(conn, os.path.join(SQL_DIR, "default_settlement_fee.sql"))
    df_dtf["loan_token"] = df_dtf["loan_token"].str.lower()
    row = df_dtf[(df_dtf["loan_token"] == loan_token) & (df_dtf["index"] == 3)]
    if row.empty:
        check_int("default_settlement_fee_cbp_3", 0, exp["default_settlement_fee_cbp_3"])
    else:
        check_int(
            "default_settlement_fee_cbp_3",
            row.iloc[0]["fee_cbp"],
            exp["default_settlement_fee_cbp_3"],
        )

    # ── default_continuous_fee.sql ────────────────────────────────────────────
    print("Verifying default_continuous_fee.sql …")
    df_dcf = run_sql(conn, os.path.join(SQL_DIR, "default_continuous_fee.sql"))
    df_dcf["loan_token"] = df_dcf["loan_token"].str.lower()
    row = df_dcf[df_dcf["loan_token"] == loan_token]
    if row.empty:
        check_int("default_continuous_fee", 0, exp["default_continuous_fee"])
    else:
        check_int("default_continuous_fee", row.iloc[0]["fee"], exp["default_continuous_fee"])

    # ── roles.sql ─────────────────────────────────────────────────────────────
    print("Verifying roles.sql …")
    df_roles = run_sql(conn, os.path.join(SQL_DIR, "roles.sql"))
    if df_roles.empty:
        fail("roles.sql: no rows")
    else:
        r = df_roles.iloc[0]
        check_str("role_setter",         r["role_setter"],         exp["role_setter"])
        check_str("fee_setter",          r["fee_setter"],          exp["fee_setter"])
        check_str("fee_claimer",         r["fee_claimer"],         exp["fee_claimer"])
        check_str("tick_spacing_setter", r["tick_spacing_setter"], exp["tick_spacing_setter"])

    # ── Summary ───────────────────────────────────────────────────────────────
    if failures:
        print(f"\nFAILURES ({len(failures)}):")
        for msg in failures:
            print(msg)
        sys.exit(1)
    else:
        print("\nAll SQL queries match expected state.")


if __name__ == "__main__":
    verify_all()
