import json
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

# ── 1. Load data ──────────────────────────────────────────────────────────────
with open("gas_data.json") as f:
    data = json.load(f)

ns = np.array([d["max_collaterals_per_borrower"] for d in data], dtype=float)
gas = np.array([d["gas"] for d in data], dtype=float)

# Sort by n (just in case)
order = np.argsort(ns)
ns, gas = ns[order], gas[order]

TARGET = 2 ** 24  # 16_777_216

# ── 2. Quadratic regression: gas ≈ a·n² + b·n + c ────────────────────────────
a, b, c = np.polyfit(ns, gas, 2)
print(f"Quadratic fit: gas ≈ {a:.4f}·n² + {b:.4f}·n + {c:.4f}")

# Solve a·n² + b·n + (c - TARGET) = 0 for the positive root.
disc = b * b - 4 * a * (c - TARGET)
if disc < 0:
    raise ValueError(f"No real solution: discriminant = {disc:.4f}")

sqrt_disc = np.sqrt(disc)
roots = [(-b + sqrt_disc) / (2 * a), (-b - sqrt_disc) / (2 * a)]
positive_roots = [r for r in roots if r > 0]
if not positive_roots:
    raise ValueError(f"No positive root found among {roots}")
n_star = min(positive_roots)
print(f"Gas reaches 2^24 at n ≈ {n_star:.2f}")

# ── 3. Plot ───────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(10, 6))

# Draw the quadratic fit smoothly from ns[0] to n_star.
n_curve = np.linspace(ns[0], n_star, 400)
gas_curve = a * n_curve ** 2 + b * n_curve + c
ax.plot(
    n_curve, gas_curve,
    color="#4C72B0", linewidth=2, linestyle="-",
    label=f"Quadratic fit: {a:.2f}·n² + {b:.2f}·n + {c:.2f}",
)
ax.scatter(ns, gas, color="#4C72B0", s=40, zorder=5, label="Data points")

# Target line
ax.axhline(
    TARGET, color="#C44E52", linewidth=1.4, linestyle="--",
    label=f"EIP-7825 Target: 2²⁴ = {TARGET:,}",
)

gas_star = a * n_star ** 2 + b * n_star + c
ax.axvline(
    n_star, color="#DD8452", linewidth=1.4, linestyle=":",
    label=f"n* ≈ {n_star:.2f}",
)
ax.plot(
    n_star, gas_star, marker="*", markersize=14,
    color="#DD8452", zorder=6, label=f"({n_star:.2f}, 2²⁴)",
)

ax.annotate(
    f"  n* ≈ {n_star:.2f}",
    xy=(n_star, gas_star),
    xytext=(n_star, gas_star * 1.15),
    arrowprops=dict(arrowstyle="->", color="#DD8452"),
    fontsize=10, color="#DD8452",
)

ax.set_xlabel("MAX_COLLATERALS_PER_BORROWER", fontsize=12)
ax.set_ylabel("Gas", fontsize=12)
ax.set_title("Gas consumption as a function of MAX_COLLATERALS_PER_BORROWER", fontsize=14)
ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, _: f"{x:,.0f}"))
ax.legend(fontsize=10)
ax.grid(True, linestyle="--", alpha=0.4)

plt.tight_layout()
plt.savefig("gas_plot.png", dpi=150)
plt.show()
print(f"\n✓ Gas reaches 2^24 at n ≈ {n_star:.4f}")
