#!/usr/bin/env python3
import json

MAX_TICK = 5820

def exact_price(tick):
    """Reference tick to price implementation matching Solidity rounding."""
    raw = 1e18 / (1 + 1.005 ** (MAX_TICK / 2 - tick))
    return round(raw / 1e12) * int(1e12)

if __name__ == "__main__":
    prices = [str(exact_price(tick)) for tick in range(MAX_TICK + 1)]
    with open("test/ticks_exact.json", "w") as f:
        json.dump({"prices": prices}, f, indent=4)
