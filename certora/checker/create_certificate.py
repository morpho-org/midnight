import json
import sys

from eth_abi import encode
from eth_account import Account
from web3 import EthereumTesterProvider, Web3

w3 = Web3(EthereumTesterProvider())

# keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
EIP712_DOMAIN_TYPEHASH = bytes.fromhex(
    "47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218"
)

# Precomputed offerTreeTypeHash(h) for h in 0..20; mirrors HashLib.offerTreeTypeHash.
OFFER_TREE_TYPE_HASHES = [
    "2b9ee710e1977dfc5778fe18c905ccc1d9e144baf3ba83be732d4da65ecb73e3",
    "3cc16189b92a85898f1d5c6e87282c8ded7c1c93b2323d5e85ae10c5f4b2b220",
    "6de37d3e570afa293a8107d4b6b1d9547616c04f42164d009c89194787b2ffa6",
    "ba3ea2ddfbf40a906fcd1b9506dbd344c062e8dcba8b5c902ceb13339f45a358",
    "e5faa865e93bc1b7b8fdf91980f54682d649683b014edd6c54b642f5a0c96977",
    "eda50f61dd2a827c6ff9fbfcd54335628dcaa78aaa4f2d118c60886219cdce2b",
    "54e2c9cc40cdc0e9ad530cf2be298f952f57af2b18b02f88274a9bbab359d23a",
    "c9d81859d60d6b21c688f4be93ca83e3be222728bb156ef5f4cf497f879f1e29",
    "d59b0c4544e0c60c8611eab0aaa402575f14ee784d22289c5d57f48c422a62d6",
    "ccad21701f34f08bb8398a3dbc77e20e4c9c424930f3a8b31485bf059e2bdb20",
    "8a42dfb49807647bfc49c906aef322aa0239d40e4cb675761e141bc7bfa530da",
    "2adc0d948b2e3ecb642661590d2eec36d4e71e9acf382deb6574371800caf198",
    "f5845dfaed016de272342f346346a49d4b1694f622144d420558a38e46ac9dad",
    "3d7df854e6294bf433b64bbb8d0a82fa875a87b45b0016db27fc5752e54126ad",
    "72a991a101708716ff427c524404ab44f4d4d1f4e7e76c0ae8b967222164b348",
    "762c88fc52cf78a54401d247790f1bdb619d51d3458d1415c20d1422197cecc4",
    "8ede2209e94c8d5f8379d733dc8712b71a3888c1c4b70f3d6b22285f70bf4286",
    "425b18f07b3ac2f641977d2c294590565dd40b5d8414610568dca64628399975",
    "7e7d98718c0180e882e5963b9bd49810096912c273dfa38d8afdd6d39fde86ec",
    "8d35d491a29d846489e19688efff3c4cc7dbd54458058d49b30294074539f0b9",
    "824e385eea1953bcbc783bf900b18aa6fba129b6908765e986cf0968b491ec4f",
]

# ABI signature for `Offer` matching src/interfaces/IMidnight.sol field order.
OFFER_ABI_TYPE = (
    "("
    "(address,(address,uint256,uint256,address)[],uint256,uint256,address,address),"
    "bool,address,uint256,uint256,uint256,bytes32,address,bytes,address,address,bool,uint256,uint256"
    ")"
)


def offer_tree_typehash(height):
    if not 0 <= height <= 20:
        raise ValueError(f"offer-tree height out of range: {height}")
    return bytes.fromhex(OFFER_TREE_TYPE_HASHES[height])


def _bytes32(v):
    raw = bytes.fromhex(v.removeprefix("0x"))
    assert len(raw) == 32, f"expected 32 bytes, got {len(raw)}"
    return raw


def _hexbytes(v):
    return bytes.fromhex(v.removeprefix("0x"))


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


# Returns the hash of an offer (mirrors HashLib.hashOffer).
def hash_offer(o):
    raw = bytes.fromhex(abi_encode_offer(o)[2:])
    return w3.to_hex(w3.solidity_keccak(["bytes"], [raw]))


# Returns the hash of a node given the hashes of its children.
def hash_node(left, right):
    return w3.to_hex(
        w3.solidity_keccak(["bytes32", "bytes32"], [_bytes32(left), _bytes32(right)])
    )


# Builds a dense certificate from a power-of-two list of offers, in leftIndex order.
def build_dense(leaves, claimed_root):
    n = len(leaves)
    assert n > 0 and (n & (n - 1)) == 0, "dense leaves count must be a power of two"

    level = [hash_offer(o) for o in leaves]
    while len(level) > 1:
        level = [hash_node(level[2 * i], level[2 * i + 1]) for i in range(len(level) // 2)]
    assert level[0].lower() == claimed_root.lower(), (
        f"dense: computed root {level[0]} != claimed root {claimed_root}"
    )

    return {
        "root": claimed_root,
        "leafLength": n,
        "leaf": [abi_encode_offer(o) for o in leaves],
    }


# Reconstructs the EIP-712 digest for an OfferTree and either signs it locally
# (`signerKey`) or accepts a precomputed (signer, v, r, s).
def build_eip712(eip712_in, root, leaf_length):
    ratifier = w3.to_checksum_address(eip712_in["ratifier"])
    chain_id = int(eip712_in["chainId"])
    height = (leaf_length - 1).bit_length()
    if 1 << height != leaf_length:
        raise ValueError(
            f"eip712 requires a balanced tree; leafLength {leaf_length} is not a power of two"
        )

    struct_hash = w3.solidity_keccak(
        ["bytes32", "bytes32"], [offer_tree_typehash(height), _bytes32(root)]
    )
    domain_separator = w3.solidity_keccak(
        ["bytes32", "uint256", "address"], [EIP712_DOMAIN_TYPEHASH, chain_id, ratifier]
    )
    digest = w3.solidity_keccak(
        ["bytes1", "bytes1", "bytes32", "bytes32"],
        [b"\x19", b"\x01", domain_separator, struct_hash],
    )

    if "signerKey" in eip712_in:
        signed = Account._sign_hash(digest, eip712_in["signerKey"])
        signer = Account.from_key(eip712_in["signerKey"]).address
        v, r, s = signed.v, signed.r.to_bytes(32, "big"), signed.s.to_bytes(32, "big")
    else:
        signer = w3.to_checksum_address(eip712_in["signer"])
        v = int(eip712_in["v"])
        r = _bytes32(eip712_in["r"])
        s = _bytes32(eip712_in["s"])

    return {
        "ratifier": ratifier,
        "chainId": chain_id,
        "height": height,
        "signer": signer,
        "v": v,
        "r": "0x" + r.hex(),
        "s": "0x" + s.hex(),
    }


def main():
    if len(sys.argv) != 2:
        print("usage: python create_certificate.py <proofs.json>", file=sys.stderr)
        sys.exit(2)

    with open(sys.argv[1]) as f:
        proofs = json.load(f)

    root = proofs["root"]
    certificate = build_dense([entry["offer"] for entry in proofs["leaves"]], root)

    if "eip712" in proofs:
        certificate["eip712"] = build_eip712(proofs["eip712"], root, certificate["leafLength"])

    with open("certificate.json", "w") as f:
        json.dump(certificate, f, indent=2)


if __name__ == "__main__":
    main()
