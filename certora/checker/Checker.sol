// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {stdJson} from "../../lib/forge-std/src/StdJson.sol";

import {OfferTree} from "../helpers/OfferTree.sol";
import {Offer, Market, CollateralParams} from "../../src/interfaces/IMidnight.sol";
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

    // Rebuild a dense tree level-by-level via the verified `newLeaf` and
    // `newInternalNode` primitives and assert the top hash matches `root`.
    // Inserts are skipped when the target slot is already populated, so duplicate
    // leaves (e.g. an `emptyOffer` repeated across padding slots) collapse into a
    // single helper slot.
    function _verifyDense(Offer[] memory leaves, bytes32 root) internal {
        require(leaves.length > 0, "no leaves");
        require((leaves.length & (leaves.length - 1)) == 0, "leaves length not power of two");

        OfferTree tree = new OfferTree();

        bytes32[] memory level = new bytes32[](leaves.length);
        for (uint256 i = 0; i < leaves.length; i++) {
            bytes32 leafHash = HashLib.hashOffer(leaves[i]);
            if (tree.isEmpty(leafHash)) tree.newLeaf(leaves[i]);
            level[i] = leafHash;
        }

        while (level.length > 1) {
            uint256 half = level.length / 2;
            bytes32[] memory next = new bytes32[](half);
            for (uint256 i = 0; i < half; i++) {
                bytes32 leftHash = level[2 * i];
                bytes32 rightHash = level[2 * i + 1];
                bytes32 nodeHash = HashLib.hashNode(leftHash, rightHash);
                if (tree.isEmpty(nodeHash)) tree.newInternalNode(nodeHash, leftHash, rightHash);
                next[i] = nodeHash;
            }
            level = next;
        }

        assertEq(level[0], root, "dense: root mismatch");
    }

    // Internal nodes must be supplied in topological order (children before parents).
    // The last id is taken as the root.
    function _verifySparse(
        Offer[] memory leaves,
        bytes32[] memory nodeIds,
        bytes32[] memory nodeLefts,
        bytes32[] memory nodeRights,
        bytes32 root
    ) internal {
        require(nodeIds.length == nodeLefts.length, "node arrays length mismatch");
        require(nodeIds.length == nodeRights.length, "node arrays length mismatch");
        require(nodeIds.length > 0, "no internal nodes");

        OfferTree tree = new OfferTree();

        for (uint256 i = 0; i < leaves.length; i++) {
            bytes32 leafHash = HashLib.hashOffer(leaves[i]);
            if (tree.isEmpty(leafHash)) tree.newLeaf(leaves[i]);
        }
        for (uint256 i = 0; i < nodeIds.length; i++) {
            if (tree.isEmpty(nodeIds[i])) {
                tree.newInternalNode(nodeIds[i], nodeLefts[i], nodeRights[i]);
            }
        }

        bytes32 rootId = nodeIds[nodeIds.length - 1];
        assertEq(tree.getHash(rootId), root, "sparse: root mismatch");
    }

    // Mirrors EcrecoverRatifier.isRatified: structHash wraps the offer-tree typehash
    // and root, the domain separator binds (chainId, ratifier), and the digest is the
    // standard EIP-712 form.
    function _verifyEip712(bytes32 root, Eip712Envelope memory env) internal {
        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(env.height), root));
        bytes32 domainSeparator =
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, env.chainId, env.ratifier));
        bytes32 digest = keccak256(bytes.concat(hex"1901", domainSeparator, structHash));
        address recovered = ecrecover(digest, env.v, env.r, env.s);
        require(recovered != address(0), "eip712: invalid signature");
        assertEq(recovered, env.signer, "eip712: signer mismatch");
    }

    function _maybeVerifyEip712(string memory json, bytes32 root, uint256 leafLength) internal {
        if (!json.keyExists(".eip712")) return;

        Eip712Envelope memory env;
        env.ratifier = json.readAddress(".eip712.ratifier");
        env.chainId = json.readUint(".eip712.chainId");
        env.height = json.readUint(".eip712.height");
        env.signer = json.readAddress(".eip712.signer");
        env.v = uint8(json.readUint(".eip712.v"));
        env.r = json.readBytes32(".eip712.r");
        env.s = json.readBytes32(".eip712.s");

        require(1 << env.height == leafLength, "eip712: height does not match leaf count");
        _verifyEip712(root, env);
    }

    function testVerifyCertificate() public {
        string memory path = string.concat(vm.projectRoot(), "/certificate.json");
        if (!vm.exists(path)) vm.skip(true, "no certificate.json at project root");

        string memory json = vm.readFile(path);
        string memory mode = json.readString(".mode");
        bytes32 root = json.readBytes32(".root");

        uint256 leafLength = json.readUint(".leafLength");
        Offer[] memory leaves = new Offer[](leafLength);
        for (uint256 i = 0; i < leafLength; i++) {
            bytes memory enc = json.readBytes(string.concat(".leaf[", vm.toString(i), "]"));
            leaves[i] = abi.decode(enc, (Offer));
        }

        bytes32 modeHash = keccak256(bytes(mode));
        if (modeHash == keccak256("dense")) {
            _verifyDense(leaves, root);
            _maybeVerifyEip712(json, root, leafLength);
        } else if (modeHash == keccak256("sparse")) {
            uint256 nodeLength = json.readUint(".nodeLength");
            bytes32[] memory ids = new bytes32[](nodeLength);
            bytes32[] memory lefts = new bytes32[](nodeLength);
            bytes32[] memory rights = new bytes32[](nodeLength);
            for (uint256 i = 0; i < nodeLength; i++) {
                string memory base = string.concat(".node[", vm.toString(i), "]");
                ids[i] = json.readBytes32(string.concat(base, ".id"));
                lefts[i] = json.readBytes32(string.concat(base, ".left"));
                rights[i] = json.readBytes32(string.concat(base, ".right"));
            }
            _verifySparse(leaves, ids, lefts, rights, root);
        } else {
            revert("unknown certificate mode");
        }
    }

    function testSyntheticDenseHeight2() public {
        Offer[] memory leaves = new Offer[](4);
        for (uint256 i = 0; i < 4; i++) leaves[i] = _dummyOffer(i);

        bytes32 h0 = HashLib.hashOffer(leaves[0]);
        bytes32 h1 = HashLib.hashOffer(leaves[1]);
        bytes32 h2 = HashLib.hashOffer(leaves[2]);
        bytes32 h3 = HashLib.hashOffer(leaves[3]);
        bytes32 leftBranch = HashLib.hashNode(h0, h1);
        bytes32 rightBranch = HashLib.hashNode(h2, h3);
        bytes32 root = HashLib.hashNode(leftBranch, rightBranch);

        _verifyDense(leaves, root);
    }

    function testSyntheticDenseHeight2DetectsRootMismatch() public {
        Offer[] memory leaves = new Offer[](4);
        for (uint256 i = 0; i < 4; i++) leaves[i] = _dummyOffer(i);

        vm.expectRevert();
        this.externalVerifyDense(leaves, bytes32(uint256(0xdeadbeef)));
    }

    function testSyntheticDenseHeight2WithEmptyPadding() public {
        Offer memory emptyOffer;
        Offer memory real = _dummyOffer(42);

        Offer[] memory leaves = new Offer[](4);
        leaves[0] = real;
        leaves[1] = emptyOffer;
        leaves[2] = emptyOffer;
        leaves[3] = emptyOffer;

        bytes32 hReal = HashLib.hashOffer(real);
        bytes32 hEmpty = HashLib.hashOffer(emptyOffer);
        bytes32 leftBranch = HashLib.hashNode(hReal, hEmpty);
        bytes32 rightBranch = HashLib.hashNode(hEmpty, hEmpty);
        bytes32 root = HashLib.hashNode(leftBranch, rightBranch);

        _verifyDense(leaves, root);
    }

    function testSyntheticDenseHeight2AllEmpty() public {
        Offer memory emptyOffer;

        Offer[] memory leaves = new Offer[](4);
        leaves[0] = emptyOffer;
        leaves[1] = emptyOffer;
        leaves[2] = emptyOffer;
        leaves[3] = emptyOffer;

        bytes32 hEmpty = HashLib.hashOffer(emptyOffer);
        bytes32 inner = HashLib.hashNode(hEmpty, hEmpty);
        bytes32 root = HashLib.hashNode(inner, inner);

        _verifyDense(leaves, root);
    }

    function testSyntheticEip712Height2() public {
        Offer[] memory leaves = new Offer[](4);
        for (uint256 i = 0; i < 4; i++) leaves[i] = _dummyOffer(i);

        bytes32 h0 = HashLib.hashOffer(leaves[0]);
        bytes32 h1 = HashLib.hashOffer(leaves[1]);
        bytes32 h2 = HashLib.hashOffer(leaves[2]);
        bytes32 h3 = HashLib.hashOffer(leaves[3]);
        bytes32 root = HashLib.hashNode(HashLib.hashNode(h0, h1), HashLib.hashNode(h2, h3));

        address ratifier = address(uint160(0xA17F1E7));
        uint256 chainId = 1;
        uint256 height = 2;
        uint256 privateKey = 0xA11CE;

        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(height), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, chainId, ratifier));
        bytes32 digest = keccak256(bytes.concat(hex"1901", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        _verifyDense(leaves, root);
        _verifyEip712(
            root,
            Eip712Envelope({
                ratifier: ratifier,
                chainId: chainId,
                height: height,
                signer: vm.addr(privateKey),
                v: v,
                r: r,
                s: s
            })
        );
    }

    function testSyntheticEip712DetectsSignerMismatch() public {
        Offer[] memory leaves = new Offer[](2);
        leaves[0] = _dummyOffer(300);
        leaves[1] = _dummyOffer(301);

        bytes32 root = HashLib.hashNode(HashLib.hashOffer(leaves[0]), HashLib.hashOffer(leaves[1]));

        address ratifier = address(uint160(0xA17F1E7));
        uint256 chainId = 1;
        uint256 height = 1;

        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(height), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, chainId, ratifier));
        bytes32 digest = keccak256(bytes.concat(hex"1901", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(0xB0B), digest);

        Eip712Envelope memory env = Eip712Envelope({
            ratifier: ratifier,
            chainId: chainId,
            height: height,
            signer: vm.addr(uint256(0xDEADBEEF)),
            v: v,
            r: r,
            s: s
        });

        vm.expectRevert();
        this.externalVerifyEip712(root, env);
    }

    function testSyntheticEip712DetectsWrongRoot() public {
        Offer[] memory leaves = new Offer[](2);
        leaves[0] = _dummyOffer(400);
        leaves[1] = _dummyOffer(401);

        bytes32 root = HashLib.hashNode(HashLib.hashOffer(leaves[0]), HashLib.hashOffer(leaves[1]));

        address ratifier = address(uint160(0xA17F1E7));
        uint256 chainId = 1;
        uint256 height = 1;
        uint256 privateKey = 0xC0FFEE;

        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(height), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, chainId, ratifier));
        bytes32 digest = keccak256(bytes.concat(hex"1901", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        Eip712Envelope memory env = Eip712Envelope({
            ratifier: ratifier,
            chainId: chainId,
            height: height,
            signer: vm.addr(privateKey),
            v: v,
            r: r,
            s: s
        });

        vm.expectRevert();
        this.externalVerifyEip712(keccak256(abi.encode(root, "tamper")), env);
    }

    function testSyntheticSparseTwoLeaves() public {
        Offer[] memory leaves = new Offer[](2);
        leaves[0] = _dummyOffer(100);
        leaves[1] = _dummyOffer(101);

        bytes32 leftHash = HashLib.hashOffer(leaves[0]);
        bytes32 rightHash = HashLib.hashOffer(leaves[1]);
        bytes32 root = HashLib.hashNode(leftHash, rightHash);

        bytes32[] memory ids = new bytes32[](1);
        bytes32[] memory lefts = new bytes32[](1);
        bytes32[] memory rights = new bytes32[](1);
        ids[0] = root;
        lefts[0] = leftHash;
        rights[0] = rightHash;

        _verifySparse(leaves, ids, lefts, rights, root);
    }

    function testSyntheticSparseDepth2OneActivePath() public {
        Offer[] memory leaves = new Offer[](3);
        leaves[0] = _dummyOffer(200);
        leaves[1] = _dummyOffer(201);
        leaves[2] = _dummyOffer(202);

        bytes32 h0 = HashLib.hashOffer(leaves[0]);
        bytes32 h1 = HashLib.hashOffer(leaves[1]);
        bytes32 hUncle = HashLib.hashOffer(leaves[2]);
        bytes32 leftBranch = HashLib.hashNode(h0, h1);
        bytes32 root = HashLib.hashNode(leftBranch, hUncle);

        bytes32[] memory ids = new bytes32[](2);
        bytes32[] memory lefts = new bytes32[](2);
        bytes32[] memory rights = new bytes32[](2);

        ids[0] = leftBranch;
        lefts[0] = h0;
        rights[0] = h1;
        ids[1] = root;
        lefts[1] = leftBranch;
        rights[1] = hUncle;

        _verifySparse(leaves, ids, lefts, rights, root);
    }

    // External wrappers so `vm.expectRevert` can catch internal-call reverts.
    function externalVerifyDense(Offer[] memory leaves, bytes32 root) external {
        _verifyDense(leaves, root);
    }

    function externalVerifyEip712(bytes32 root, Eip712Envelope memory env) external {
        _verifyEip712(root, env);
    }

    // Distinct dummy offers, distinguished by `tick`.
    function _dummyOffer(uint256 nonce) internal pure returns (Offer memory o) {
        o.market.loanToken = address(uint160(0x1000 + nonce));
        o.market.collateralParams = new CollateralParams[](0);
        o.maker = address(uint160(0x2000 + nonce));
        o.tick = nonce;
        o.maxUnits = 1;
        o.maxAssets = 1;
    }
}
