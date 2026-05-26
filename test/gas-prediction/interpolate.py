import json
import os
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

# ── 0. Detect hardfork from foundry.toml ─────────────────────────────────────
def _is_tempo_hardfork():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    toml_path = os.path.join(script_dir, "..", "..", "foundry.toml")
    try:
        with open(toml_path) as f:
            content = f.read()
        import re
        return bool(re.search(r'hardfork\s*=\s*"tempo:T4"', content))
    except FileNotFoundError:
        return False

IS_TEMPO = _is_tempo_hardfork()
GAS_LABEL = "Tempo gas cost" if IS_TEMPO else "Gas"
NETWORK_LABEL = "Tempo" if IS_TEMPO else "Ethereum"

# ── 1. Load data ──────────────────────────────────────────────────────────────
with open("gas_data.json") as f:
    data = json.load(f)

ns = np.array([d["max_collaterals_per_borrower"] for d in data], dtype=float)
order = np.argsort(ns)
ns = ns[order]

SERIES = {
    "basic":    ("gas_basic",    "#4C72B0", "Basic (no DEX swap)"),
    "one_hop":  ("gas_one_hop",  "#55A868", "One Uniswap V3 swap / collateral"),
    "two_hops": ("gas_two_hops", "#C44E52", "Two Uniswap V3 swaps / collateral"),
}

# Fall back to legacy single-key format so old gas_data.json files still work.
def _load_series(key: str) -> np.ndarray | None:
    if key in data[0]:
        return np.array([d[key] for d in data], dtype=float)[order]
    if key == "gas_basic" and "gas" in data[0]:
        return np.array([d["gas"] for d in data], dtype=float)[order]
    return None

TARGET = 2 ** 24  # 16_777_216

# ── 2. Fit quadratics and find n* for each series ────────────────────────────
fits = {}
for name, (key, color, label) in SERIES.items():
    gas = _load_series(key)
    if gas is None:
        continue
    a, b, c = np.polyfit(ns, gas, 2)
    disc = b * b - 4 * a * (c - TARGET)
    if disc < 0:
        print(f"[{name}] No real solution: discriminant = {disc:.4f}")
        continue
    sqrt_disc = np.sqrt(disc)
    roots = [(-b + sqrt_disc) / (2 * a), (-b - sqrt_disc) / (2 * a)]
    positive_roots = [r for r in roots if r > 0]
    if not positive_roots:
        print(f"[{name}] No positive root found among {roots}")
        continue
    n_star = min(positive_roots)
    fits[name] = dict(gas=gas, a=a, b=b, c=c, n_star=n_star, color=color, label=label)
    print(
        f"[{name:8s}] fit: {a:.4f}·n² + {b:.4f}·n + {c:.4f}  →  "
        f"gas reaches 2^24 at n* ≈ {n_star:.2f}"
    )

# ── 3. Plot ───────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(11, 7))

n_max_curve = max(f["n_star"] for f in fits.values())
n_curve = np.linspace(ns[0], n_max_curve, 500)

for name, f in fits.items():
    a, b, c = f["a"], f["b"], f["c"]
    gas_curve = a * n_curve ** 2 + b * n_curve + c
    n_star = f["n_star"]
    color = f["color"]
    short_label = f["label"]

    ax.plot(
        n_curve, gas_curve,
        color=color, linewidth=2,
        label=f"{short_label}: {a:.2f}·n² + {b:.2f}·n + {c:.2f}",
    )
    ax.scatter(ns, f["gas"], color=color, s=40, zorder=5)
    ax.axvline(n_star, color=color, linewidth=1.2, linestyle=":", alpha=0.7)
    ax.plot(
        n_star, TARGET, marker="*", markersize=12, color=color, zorder=6,
        label=f"n* ≈ {n_star:.2f} ({short_label})",
    )

ax.axhline(
    TARGET, color="black", linewidth=1.4, linestyle="--",
    label=f"EIP-7825 Target: 2²⁴ = {TARGET:,}",
)

ax.set_xlabel("MAX_COLLATERALS_PER_BORROWER", fontsize=12)
ax.set_ylabel(GAS_LABEL, fontsize=12)
ax.set_title(
    f"Midnight full liquidation gas cost on {NETWORK_LABEL} as a function of MAX_COLLATERALS_PER_BORROWER",
    fontsize=14,
)
ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, _: f"{x:,.0f}"))
ax.legend(fontsize=9)
ax.grid(True, linestyle="--", alpha=0.4)

plt.tight_layout()
plt.savefig("gas_plot.png", dpi=150)
plt.show()

print()
for name, f in fits.items():
    print(f"✓ [{f['label']}] gas reaches 2^24 at n* ≈ {f['n_star']:.4f}")
