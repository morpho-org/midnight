// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./interfaces/IHooks.sol";
import "./libraries/ConstantsLib.sol";
import {IMorpho, MarketParams} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";

contract MarketV1LiquidityCallback {
    address public immutable TERMS;
    address public immutable MARKET_V1;

    constructor(address marketV1, address terms) {
        TERMS = terms;
        MARKET_V1 = marketV1;
    }

    function hook(Term calldata, address owner, uint256 assets, uint256, bytes calldata data) external {
        require(msg.sender == TERMS, "unauthorized");

        (MarketParams memory marketParams, address onBehalf) = abi.decode(data, (MarketParams, address));

        require(IMorpho(MARKET_V1).isAuthorized(owner, onBehalf), "unauthorized");
        IMorpho(MARKET_V1).withdraw(marketParams, assets, 0, onBehalf, owner);
    }
}
