// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IMorpho, MarketParams} from "morpho-blue/src/interfaces/IMorpho.sol";
import {Market} from "../interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS} from "../libraries/ConstantsLib.sol";
import {IBlueBuyCallback} from "./interfaces/IBlueBuyCallback.sol";

contract BlueBuyCallback is IBlueBuyCallback {
    address public immutable OWNER;
    address public immutable MIDNIGHT;
    address public immutable BLUE;

    constructor(address _owner, address _midnight, address _blue) {
        OWNER = _owner;
        MIDNIGHT = _midnight;
        BLUE = _blue;

        IMorpho(BLUE).setAuthorization(OWNER, true);
    }

    function onBuy(
        bytes32,
        Market memory market,
        uint256 buyerAssets,
        uint256,
        uint256,
        address buyer,
        bytes memory data
    ) external returns (bytes32) {
        require(msg.sender == MIDNIGHT, NotMidnight());
        require(buyer == OWNER, NotOwnerBuyer());

        MarketParams memory blueMarketParams = abi.decode(data, (MarketParams));
        require(blueMarketParams.loanToken == market.loanToken, InconsistentLoanToken());

        if (buyerAssets > 0) IMorpho(BLUE).withdraw(blueMarketParams, buyerAssets, 0, address(this), address(this));
        safeApprove(market.loanToken, MIDNIGHT, buyerAssets);

        return CALLBACK_SUCCESS;
    }

    function safeApprove(address token, address spender, uint256 value) internal {
        (bool success, bytes memory returndata) = token.call(abi.encodeWithSelector(0x095ea7b3, spender, value));
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returndata, 0x20), mload(returndata))
            }
        }
        require(returndata.length == 0 || abi.decode(returndata, (bool)), ApproveReturnedFalse());
    }
}
