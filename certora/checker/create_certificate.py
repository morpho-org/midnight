import json
import sys

from eth_abi import encode
from web3 import Web3

w3 = Web3()

COLLATERAL_PARAMS_TYPEHASH = bytes.fromhex(
    "af44a88eb50ebdbbebd980e5a23045c44f61ece5f80ab708a1bbe8718102e6af"
)
MARKET_TYPEHASH = bytes.fromhex(
    "358117e98511cc3df97175dca58053b06675b43ad090b0553f8a1eff008b6e2e"
)
OFFER_TYPEHASH = bytes.fromhex(
    "980a4cfc9766df84667f316d76e10cefc8caf04fb4cd4a9fca00a8e7b34f619c"
)

# ABI signature for `Offer` matching src/interfaces/IMidnight.sol field order.
OFFER_ABI_TYPE = (
    "("
    "(address,(address,uint256,uint256,address)[],uint256,uint256,address,address),"
    "bool,address,uint256,uint256,uint256,bytes32,address,bytes,address,address,bool,uint256,uint256"
    ")"
)
INTERNAL_NODE_ABI_TYPE = "(bytes32,bytes32,bytes32)"


def _bytes32(v):
    raw = bytes.fromhex(v.removeprefix("0x"))
    assert len(raw) == 32, f"expected 32 bytes, got {len(raw)}"
    return raw


def _hexbytes(v):
    return bytes.fromhex(v.removeprefix("0x"))


def _keccak_abi(types, values):
    return w3.keccak(encode(types, values))


# Returns the abi-encoded form of an Offer, ready for `abi.decode(bytes, (Offer))`.
def abi_encode_offer(o):
    m = o["market"]
    market = (
        w3.to_checksum_address(m["loanToken"]),
        [
            (
                w3.to_checksum_address(cp["token"]),
                int(cp["lltv"]),
                int(cp["maxLif"]),
                w3.to_checksum_address(cp["oracle"]),
            )
            for cp in m["collateralParams"]
        ],
        int(m["maturity"]),
        int(m["rcfThreshold"]),
        w3.to_checksum_address(m["enterGate"]),
        w3.to_checksum_address(m["liquidatorGate"]),
    )
    offer = (
        market,
        bool(o["buy"]),
        w3.to_checksum_address(o["maker"]),
        int(o["start"]),
        int(o["expiry"]),
        int(o["tick"]),
        _bytes32(o["group"]),
        w3.to_checksum_address(o["callback"]),
        _hexbytes(o["callbackData"]),
        w3.to_checksum_address(o["receiverIfMakerIsSeller"]),
        w3.to_checksum_address(o["ratifier"]),
        bool(o["reduceOnly"]),
        int(o["maxUnits"]),
        int(o["maxAssets"]),
    )
    return "0x" + encode([OFFER_ABI_TYPE], [offer]).hex()


def abi_encode_node(node_id, left, right):
    node = (_bytes32(node_id), _bytes32(left), _bytes32(right))
    return "0x" + encode([INTERNAL_NODE_ABI_TYPE], [node]).hex()


def hash_collateral_params(cp):
    return _keccak_abi(
        ["bytes32", "address", "uint256", "uint256", "address"],
        [
            COLLATERAL_PARAMS_TYPEHASH,
            w3.to_checksum_address(cp["token"]),
            int(cp["lltv"]),
            int(cp["maxLif"]),
            w3.to_checksum_address(cp["oracle"]),
        ],
    )


def hash_market(m):
    collateral_params_hashes = b"".join(
        hash_collateral_params(cp) for cp in m["collateralParams"]
    )
    collateral_params_hash = w3.keccak(collateral_params_hashes)
    return _keccak_abi(
        ["bytes32", "address", "bytes32", "uint256", "uint256", "address", "address"],
        [
            MARKET_TYPEHASH,
            w3.to_checksum_address(m["loanToken"]),
            collateral_params_hash,
            int(m["maturity"]),
            int(m["rcfThreshold"]),
            w3.to_checksum_address(m["enterGate"]),
            w3.to_checksum_address(m["liquidatorGate"]),
        ],
    )


# Returns the hash of an offer (mirrors HashLib.hashOffer).
def hash_offer(o):
    return w3.to_hex(
        _keccak_abi(
            [
                "bytes32",
                "bytes32",
                "bool",
                "address",
                "uint256",
                "uint256",
                "uint256",
                "bytes32",
                "address",
                "bytes32",
                "address",
                "address",
                "bool",
                "uint256",
                "uint256",
            ],
            [
                OFFER_TYPEHASH,
                hash_market(o["market"]),
                bool(o["buy"]),
                w3.to_checksum_address(o["maker"]),
                int(o["start"]),
                int(o["expiry"]),
                int(o["tick"]),
                _bytes32(o["group"]),
                w3.to_checksum_address(o["callback"]),
                w3.keccak(_hexbytes(o["callbackData"])),
                w3.to_checksum_address(o["receiverIfMakerIsSeller"]),
                w3.to_checksum_address(o["ratifier"]),
                bool(o["reduceOnly"]),
                int(o["maxUnits"]),
                int(o["maxAssets"]),
            ],
        )
    )


# Returns the hash of a node given the hashes of its children.
def hash_node(left, right):
    return w3.to_hex(w3.keccak(_bytes32(left) + _bytes32(right)))


# Builds a dense certificate from a power-of-two list of offers, in leftIndex order.
def build_dense(leaves, claimed_root):
    n = len(leaves)
    assert n > 0 and (n & (n - 1)) == 0, "dense leaves count must be a power of two"

    leaf_instructions = {}
    node_instructions = {}

    level = [hash_offer(o) for o in leaves]
    for leaf, leaf_hash in zip(leaves, level):
        encoded_leaf = abi_encode_offer(leaf)
        previous = leaf_instructions.setdefault(leaf_hash, encoded_leaf)
        assert previous == encoded_leaf, "leaf hash collides with a different offer"

    while len(level) > 1:
        next_level = []
        for i in range(len(level) // 2):
            left = level[2 * i]
            right = level[2 * i + 1]
            node_hash = hash_node(left, right)
            assert (
                node_hash not in leaf_instructions
            ), "internal node id collides with a leaf id"
            encoded_node = abi_encode_node(node_hash, left, right)
            previous = node_instructions.setdefault(node_hash, encoded_node)
            assert previous == encoded_node, "internal node id collides with different children"
            next_level.append(node_hash)
        level = next_level

    assert level[0].lower() == claimed_root.lower(), (
        f"dense: computed root {level[0]} != claimed root {claimed_root}"
    )

    return {
        "root": claimed_root,
        "treeLeafLength": n,
        "leafLength": len(leaf_instructions),
        "leaf": list(leaf_instructions.values()),
        "nodeLength": len(node_instructions),
        "node": list(node_instructions.values()),
    }


def main():
    if len(sys.argv) != 2:
        print("usage: python create_certificate.py <proofs.json>", file=sys.stderr)
        sys.exit(2)

    with open(sys.argv[1]) as f:
        proofs = json.load(f)

    root = proofs["root"]
    certificate = build_dense([entry["offer"] for entry in proofs["leaves"]], root)

    with open("certificate.json", "w") as f:
        json.dump(certificate, f, indent=2)


if __name__ == "__main__":
    main()
