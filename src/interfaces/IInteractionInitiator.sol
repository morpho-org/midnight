// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

interface IInteractionInitiator {
    function interactionCallback(bytes calldata data) external;
}
