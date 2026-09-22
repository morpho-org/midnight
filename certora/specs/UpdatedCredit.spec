// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

// The up-to-date credit of a position after slashing and fee accrual.
function updatedCredit(env e, Midnight.Market market, bytes32 id, address user) returns uint128 {
    uint128 newCredit;
    newCredit, _, _ = updatePositionView(e, market, id, user);
    return newCredit;
}
