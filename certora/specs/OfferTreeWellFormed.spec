// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

// Verifies that the tree construction via `newLeaf` and `newInternalNode`
// preserves `isWellFormed` for every node id. This justifies using the helper
// as a ghost tree to reason about Midnight's runtime merkle verification.

methods {
    function isEmpty(bytes32) external returns (bool) envfree;
    function isWellFormed(bytes32) external returns (bool) envfree;
}

strong invariant zeroIsEmpty()
    isEmpty(to_bytes32(0));

strong invariant wellFormed(bytes32 id)
    isWellFormed(id)
    {
        preserved {
            requireInvariant zeroIsEmpty();
        }
    }
