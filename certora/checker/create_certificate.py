import json
import sys

from eth_abi import encode
from web3 import Web3

w3 = Web3()

# Constants from src/ratifiers/libraries/HashLib.sol (checked against the type
# strings in test/HashLibTest.sol by _check_typehashes below).
COLLATERAL_PARAMS_TYPE = b"CollateralParams(address token,uint256 lltv,uint256 liquidationCursor,address oracle)"
MARKET_TYPE = b"Market(uint256 chainId,address midnight,address loanToken,CollateralParams[] collateralParams,uint256 maturity,uint256 rcfThreshold,address enterGate,address liquidatorGate)"
OFFER_TYPE = b"Offer(Market market,bool buy,address maker,uint256 start,uint256 expiry,uint256 tick,bytes32 group,address callback,bytes callbackData,address receiverIfMakerIsSeller,address ratifier,bool reduceOnly,uint128 maxUnits,uint128 maxAssets,uint256 continuousFeeCap)"

COLLATERAL_PARAMS_TYPEHASH = bytes.fromhex(
    "39ed3f928d24fd00574b1a02aba9c2483abcf5d9a3a366118c9a5aa29885b841"
)
MARKET_TYPEHASH = bytes.fromhex(
    "510b3862f3816a109c9340b76972e8a30984246be06e034ae12ed2934220391a"
)
OFFER_TYPEHASH = bytes.fromhex(
    "9905214264a9fb7b6cc1b0e33db7a04687c6e4185a84755d29914314aa9d8906"
)

# ABI signature for `Offer` matching src/interfaces/IMidnight.sol field order.
OFFER_ABI_TYPE = (
    "("
    "(uint256,address,address,(address,uint256,uint256,address)[],uint256,uint256,address,address),"
    "bool,address,uint256,uint256,uint256,bytes32,address,bytes,address,address,bool,uint128,uint128,uint256"
    ")"
)
INTERNAL_NODE_ABI_TYPE = "(bytes32,bytes32,bytes32)"


# Safety checks use this instead of `assert`, which is stripped under `python -O`.
def _require(cond, msg):
    if not cond:
        raise ValueError(msg)


def _bytes32(v):
    raw = bytes.fromhex(v.removeprefix("0x"))
    _require(len(raw) == 32, f"expected 32 bytes, got {len(raw)}")
    return raw


def _hexbytes(v):
    return bytes.fromhex(v.removeprefix("0x"))


def _keccak_abi(types, values):
    return w3.keccak(encode(types, values))


# Pin the hardcoded typehashes to the EIP-712 type strings (mirrors test/HashLibTest.sol).
def _check_typehashes():
    _require(
        w3.keccak(COLLATERAL_PARAMS_TYPE) == COLLATERAL_PARAMS_TYPEHASH,
        "COLLATERAL_PARAMS_TYPEHASH does not match its type string",
    )
    _require(
        w3.keccak(MARKET_TYPE + COLLATERAL_PARAMS_TYPE) == MARKET_TYPEHASH,
        "MARKET_TYPEHASH does not match its type string",
    )
    _require(
        w3.keccak(OFFER_TYPE + COLLATERAL_PARAMS_TYPE + MARKET_TYPE) == OFFER_TYPEHASH,
        "OFFER_TYPEHASH does not match its type string",
    )


# Returns the abi-encoded form of an Offer, ready for `abi.decode(bytes, (Offer))`.
def abi_encode_offer(o):
    m = o["market"]
    market = (
        int(m["chainId"]),
        w3.to_checksum_address(m["midnight"]),
        w3.to_checksum_address(m["loanToken"]),
        [
            (
                w3.to_checksum_address(cp["token"]),
                int(cp["lltv"]),
                int(cp["liquidationCursor"]),
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
        int(o["continuousFeeCap"]),
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
            int(cp["liquidationCursor"]),
            w3.to_checksum_address(cp["oracle"]),
        ],
    )


def hash_market(m):
    collateral_params_hashes = b"".join(
        hash_collateral_params(cp) for cp in m["collateralParams"]
    )
    collateral_params_hash = w3.keccak(collateral_params_hashes)
    return _keccak_abi(
        [
            "bytes32",
            "uint256",
            "address",
            "address",
            "bytes32",
            "uint256",
            "uint256",
            "address",
            "address",
        ],
        [
            MARKET_TYPEHASH,
            int(m["chainId"]),
            w3.to_checksum_address(m["midnight"]),
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
                "uint128",
                "uint128",
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
                int(o["continuousFeeCap"]),
            ],
        )
    )


# Returns the hash of a node given the hashes of its children.
def hash_node(left, right):
    return w3.to_hex(w3.keccak(_bytes32(left) + _bytes32(right)))


# Builds a certificate from a power-of-two list of offers, in leftIndex order, by pairing
# leaves level-by-level into a perfect binary tree.
def build_certificate(leaves, claimed_root):
    n = len(leaves)
    _require(n > 0 and (n & (n - 1)) == 0, "leaves count must be a power of two")

    leaf_instructions = {}
    node_instructions = {}

    level = [hash_offer(o) for o in leaves]
    for leaf, leaf_hash in zip(leaves, level):
        encoded_leaf = abi_encode_offer(leaf)
        previous = leaf_instructions.setdefault(leaf_hash, encoded_leaf)
        _require(previous == encoded_leaf, "leaf hash collides with a different offer")

    while len(level) > 1:
        next_level = []
        for i in range(len(level) // 2):
            left = level[2 * i]
            right = level[2 * i + 1]
            node_hash = hash_node(left, right)
            _require(node_hash not in leaf_instructions, "internal node id collides with a leaf id")
            encoded_node = abi_encode_node(node_hash, left, right)
            previous = node_instructions.setdefault(node_hash, encoded_node)
            _require(previous == encoded_node, "internal node id collides with different children")
            next_level.append(node_hash)
        level = next_level

    _require(
        level[0].lower() == claimed_root.lower(),
        f"computed root {level[0]} != claimed root {claimed_root}",
    )

    return {
        "root": claimed_root,
        "leafLength": len(leaf_instructions),
        "leaf": list(leaf_instructions.values()),
        "nodeLength": len(node_instructions),
        "node": list(node_instructions.values()),
    }


def main():
    if len(sys.argv) != 2:
        print("usage: python create_certificate.py <proofs.json>", file=sys.stderr)
        sys.exit(2)

    _check_typehashes()

    with open(sys.argv[1]) as f:
        proofs = json.load(f)

    root = proofs["root"]
    certificate = build_certificate([entry["offer"] for entry in proofs["leaves"]], root)

    with open("certificate.json", "w") as f:
        json.dump(certificate, f, indent=2)


if __name__ == "__main__":
    main()
