// SPDX-License-Identifier: GPL-2.0-or-later

// Leaves store a fixed-size pre-image so isWellFormed can re-hash them without dynamic loops.

methods {
    function isEmpty(bytes32) external returns (bool) envfree;
    function isWellFormed(bytes32) external returns (bool) envfree;
}

// The zero node remains empty.
strong invariant zeroIsEmpty()
    isEmpty(to_bytes32(0));

// Every node remains well-formed.
strong invariant wellFormed(bytes32 id)
    isWellFormed(id)
    {
        preserved {
            requireInvariant zeroIsEmpty();
        }
    }
