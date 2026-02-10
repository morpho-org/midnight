#!/usr/bin/env python3
import json

TICK_RANGE = 990

def exact_price(tick):
    """Reference tick to price implementation."""
    return int(1e18 / (1 + 1.025 ** (TICK_RANGE / 2 - tick)))

if __name__ == "__main__":
    prices = [str(exact_price(tick)) for tick in range(TICK_RANGE + 1)]
    with open("test/ticks_exact.json", "w") as f:
        json.dump({"prices": prices}, f)
