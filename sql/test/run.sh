#!/usr/bin/env bash
# Runs the Forge scenario test then verifies all SQL queries with DuckDB.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

echo "=== Generating test scenario ==="
forge test --match-test testGenerateScenario -vv

echo ""
echo "=== Verifying SQL queries ==="
uv run --with-requirements sql/test/requirements.txt python3 sql/test/verify.py
