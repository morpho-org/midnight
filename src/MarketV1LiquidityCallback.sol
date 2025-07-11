// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "./interfaces/IHook.sol";
import "./libraries/ConstantsLib.sol";
import "../lib/morpho-blue/src/interfaces/IMorpho.sol";

contract MarketV1LiquidityCallback {
    address public immutable TERMS;
    address public immutable MARKET_V1;

    constructor(address marketV1, address terms) {
        TERMS = terms;
        MARKET_V1 = marketV1;
    }

    function hook(Term calldata, uint256 assets, uint256, bool, Trade calldata trade, uint256 index) external {
        require(msg.sender == TERMS, "unauthorized");

        (MarketParams memory marketParams, address onBehalf) =
            abi.decode(trade.offer.hooks[index].data, (MarketParams, address));

        require(IMorpho(MARKET_V1).isAuthorized(trade.offer.owner, onBehalf), "unauthorized");
        IMorpho(MARKET_V1).withdraw(marketParams, assets, 0, onBehalf, trade.offer.owner);
    }
}
