#!/usr/bin/env python3
import json

MAX_TICK = 990

def exact_price(tick):
    """Reference tick to price implementation."""
    return int(1e18 / (1 + 1.025 ** (MAX_TICK / 2 - tick)))

if __name__ == "__main__":
    prices = [str(exact_price(tick)) for tick in range(MAX_TICK + 1)]
    with open("test/ticks_exact.json", "w") as f:
        json.dump({"prices": prices}, f)
