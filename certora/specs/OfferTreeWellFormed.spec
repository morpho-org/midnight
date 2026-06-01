// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function isEmpty(bytes32) external returns (bool) envfree;
    function isWellFormed(bytes32) external returns (bool) envfree;
}

// The zero node is empty, so it can serve as the canonical empty child of every node in the tree.
strong invariant zeroIsEmpty()
    isEmpty(to_bytes32(0));

// Every node of the tree is well-formed, which is what makes the membership result in OfferTreeMembership.spec sound.
strong invariant wellFormed(bytes32 id)
    isWellFormed(id)
{ preserved {
    requireInvariant zeroIsEmpty();
  }
}
