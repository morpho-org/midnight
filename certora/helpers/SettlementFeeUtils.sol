// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IMidnight} from "../../src/interfaces/IMidnight.sol";
import {CBP} from "../../src/libraries/ConstantsLib.sol";

contract SettlementFeeUtils {
    /// @dev Mirrors Midnight.settlementFee but reads the loan token's default settlement fee cbps (in Solidity) instead
    /// of the market state. This is the fee a freshly created market applies, since touchMarket copies these defaults
    /// into the market state.
    function defaultSettlementFee(IMidnight midnight, address loanToken, uint256 timeToMaturity)
        external
        view
        returns (uint256)
    {
        uint16[7] memory settlementFeeCbp;
        settlementFeeCbp[0] = midnight.defaultSettlementFeeCbp(loanToken, 0);
        settlementFeeCbp[1] = midnight.defaultSettlementFeeCbp(loanToken, 1);
        settlementFeeCbp[2] = midnight.defaultSettlementFeeCbp(loanToken, 2);
        settlementFeeCbp[3] = midnight.defaultSettlementFeeCbp(loanToken, 3);
        settlementFeeCbp[4] = midnight.defaultSettlementFeeCbp(loanToken, 4);
        settlementFeeCbp[5] = midnight.defaultSettlementFeeCbp(loanToken, 5);
        settlementFeeCbp[6] = midnight.defaultSettlementFeeCbp(loanToken, 6);

        if (timeToMaturity >= 360 days) return settlementFeeCbp[6] * CBP;

        // forgefmt: disable-start
        (uint256 start, uint256 end, uint256 feeLower, uint256 feeUpper) =
            timeToMaturity < 1 days   ? (  0 days,   1 days, settlementFeeCbp[0] * CBP, settlementFeeCbp[1] * CBP) :
            timeToMaturity < 7 days   ? (  1 days,   7 days, settlementFeeCbp[1] * CBP, settlementFeeCbp[2] * CBP) :
            timeToMaturity < 30 days  ? (  7 days,  30 days, settlementFeeCbp[2] * CBP, settlementFeeCbp[3] * CBP) :
            timeToMaturity < 90 days  ? ( 30 days,  90 days, settlementFeeCbp[3] * CBP, settlementFeeCbp[4] * CBP) :
            timeToMaturity < 180 days ? ( 90 days, 180 days, settlementFeeCbp[4] * CBP, settlementFeeCbp[5] * CBP) :
                                        (180 days, 360 days, settlementFeeCbp[5] * CBP, settlementFeeCbp[6] * CBP);
        // forgefmt: disable-end

        return (feeLower * (end - timeToMaturity) + feeUpper * (timeToMaturity - start)) / (end - start);
    }
}
