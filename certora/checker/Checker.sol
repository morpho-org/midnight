// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {stdJson} from "../../lib/forge-std/src/StdJson.sol";

import {OfferTree} from "../helpers/OfferTree.sol";
import {Offer} from "../../src/interfaces/IMidnight.sol";
import {HashLib} from "../../src/ratifiers/libraries/HashLib.sol";
import {EIP712_DOMAIN_TYPEHASH} from "../../src/ratifiers/interfaces/IEcrecoverRatifier.sol";

contract Checker is Test {
    using stdJson for string;

    struct Eip712Envelope {
        address ratifier;
        uint256 chainId;
        uint256 height;
        address signer;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct InternalNode {
        bytes32 id;
        bytes32 left;
        bytes32 right;
    }

    // Replay the certificate through the verified `newLeaf` and `newInternalNode`
    // primitives, then assert that the final certificate item matches `root`.
    function _verifyCertificate(Offer[] memory leaves, InternalNode[] memory nodes, bytes32 root) internal {
        require(leaves.length > 0, "no leaves");
        require(nodes.length > 0 || leaves.length == 1, "missing internal nodes");

        OfferTree tree = new OfferTree();

        for (uint256 i = 0; i < leaves.length; i++) {
            tree.newLeaf(leaves[i]);
        }

        bytes32 rootId = HashLib.hashOffer(leaves[0]);
        for (uint256 i = 0; i < nodes.length; i++) {
            InternalNode memory node = nodes[i];
            tree.newInternalNode(node.id, node.left, node.right);
            rootId = node.id;
        }

        assertTrue(!tree.isEmpty(rootId), "empty root");
        assertEq(tree.getHash(rootId), root, "mismatched roots");
    }

    // Mirrors EcrecoverRatifier.isRatified: structHash wraps the offer-tree typehash
    // and root, the domain separator binds (chainId, ratifier), and the digest is the
    // standard EIP-712 form.
    function _verifyEip712(bytes32 root, Eip712Envelope memory env) internal pure {
        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(env.height), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, env.chainId, env.ratifier));
        bytes32 digest = keccak256(bytes.concat(hex"1901", domainSeparator, structHash));
        address recovered = ecrecover(digest, env.v, env.r, env.s);
        require(recovered != address(0), "eip712: invalid signature");
        assertEq(recovered, env.signer, "eip712: signer mismatch");
    }

    function _maybeVerifyEip712(string memory json, bytes32 root) internal view {
        if (!json.keyExists(".eip712")) return;

        Eip712Envelope memory env;
        env.ratifier = json.readAddress(".eip712.ratifier");
        env.chainId = json.readUint(".eip712.chainId");
        env.height = json.readUint(".eip712.height");
        env.signer = json.readAddress(".eip712.signer");
        env.v = uint8(json.readUint(".eip712.v"));
        env.r = json.readBytes32(".eip712.r");
        env.s = json.readBytes32(".eip712.s");

        if (json.keyExists(".treeLeafLength")) {
            require(1 << env.height == json.readUint(".treeLeafLength"), "eip712: height does not match leaf count");
        }
        _verifyEip712(root, env);
    }

    function testVerifyCertificate() public {
        string memory path = string.concat(vm.projectRoot(), "/certificate.json");
        if (!vm.exists(path)) vm.skip(true, "no certificate.json at project root");

        string memory json = vm.readFile(path);
        bytes32 root = json.readBytes32(".root");

        uint256 leafLength = json.readUint(".leafLength");
        Offer[] memory leaves = new Offer[](leafLength);
        for (uint256 i = 0; i < leafLength; i++) {
            bytes memory enc = json.readBytes(string.concat(".leaf[", vm.toString(i), "]"));
            leaves[i] = abi.decode(enc, (Offer));
        }

        uint256 nodeLength = json.readUint(".nodeLength");
        InternalNode[] memory nodes = new InternalNode[](nodeLength);
        for (uint256 i = 0; i < nodeLength; i++) {
            bytes memory enc = json.readBytes(string.concat(".node[", vm.toString(i), "]"));
            nodes[i] = abi.decode(enc, (InternalNode));
        }

        _verifyCertificate(leaves, nodes, root);
        _maybeVerifyEip712(json, root);
    }
}
