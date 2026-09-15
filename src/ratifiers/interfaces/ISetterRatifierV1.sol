// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IRatifier} from "../../interfaces/IRatifier.sol";

bytes32 constant SET_IS_ROOT_RATIFIED_SUCCESS = keccak256("morpho.midnight.setIsRootRatifiedSuccess");

interface ISetterRatifierV1 is IRatifier {
    function setIsRootRatified(address maker, bytes32 root, bool newIsRootRatified) external returns (bytes32);
    function setIsRootRatifiedWithSig(
        address maker,
        bytes32 root,
        bool newIsRootRatified,
        uint128 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes32);

    function isRootRatified(address maker, bytes32 root) external view returns (bool);
}
