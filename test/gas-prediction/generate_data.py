"""Sweep MAX_COLLATERALS_PER_BORROWER and capture the gas reported by
testGasLiquidateMaxCollaterals at each value, writing the result to
gas_data.json (the format consumed by interpolate.py).

Usage:
    python generate_data.py [--start N] [--stop N] [--step N] [--output PATH]

Defaults sweep N in {10, 15, 20, ..., 50}.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
CONSTANTS_FILE = REPO_ROOT / "src" / "libraries" / "ConstantsLib.sol"
DEFAULT_OUTPUT = SCRIPT_DIR / "gas_data.json"

CONSTANT_RE = re.compile(r"(uint256\s+constant\s+MAX_COLLATERALS_PER_BORROWER\s*=\s*)(\d+)(\s*;)")
GAS_LOG_RE = re.compile(r"Gas max-collats liquidation\s+(\d+)")


def read_constant() -> int:
    text = CONSTANTS_FILE.read_text()
    m = CONSTANT_RE.search(text)
    if not m:
        raise RuntimeError(f"MAX_COLLATERALS_PER_BORROWER not found in {CONSTANTS_FILE}")
    return int(m.group(2))


def write_constant(value: int) -> None:
    text = CONSTANTS_FILE.read_text()
    new_text, n = CONSTANT_RE.subn(rf"\g<1>{value}\g<3>", text, count=1)
    if n != 1:
        raise RuntimeError(f"Failed to substitute MAX_COLLATERALS_PER_BORROWER in {CONSTANTS_FILE}")
    CONSTANTS_FILE.write_text(new_text)


def run_test() -> int:
    result = subprocess.run(
        ["forge", "test", "--match-test", "testGasLiquidateMaxCollaterals", "-vv"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    output = result.stdout + result.stderr
    if result.returncode != 0:
        sys.stderr.write(output)
        raise RuntimeError("forge test failed")
    m = GAS_LOG_RE.search(output)
    if not m:
        sys.stderr.write(output)
        raise RuntimeError("Could not parse 'Gas max-collats liquidation' from forge output")
    return int(m.group(1))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", type=int, default=10)
    parser.add_argument("--stop", type=int, default=50, help="inclusive")
    parser.add_argument("--step", type=int, default=5)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    values = list(range(args.start, args.stop + 1, args.step))
    if not values:
        raise SystemExit("Empty sweep range")

    original = read_constant()
    print(f"Original MAX_COLLATERALS_PER_BORROWER = {original}")
    print(f"Sweeping over {values}")

    results = []
    try:
        for v in values:
            write_constant(v)
            gas = run_test()
            print(f"  MAX_COLLATERALS_PER_BORROWER = {v:>3} -> gas = {gas:,}")
            results.append({"max_collaterals_per_borrower": v, "gas": gas})
    finally:
        write_constant(original)
        print(f"Restored MAX_COLLATERALS_PER_BORROWER = {original}")

    args.output.write_text(json.dumps(results, indent=2) + "\n")
    print(f"Wrote {len(results)} rows to {args.output}")


if __name__ == "__main__":
    main()
