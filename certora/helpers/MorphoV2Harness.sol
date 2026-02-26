// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.31;

import {MorphoV2} from "../../src/MorphoV2.sol";
import {IdLib} from "../../src/libraries/IdLib.sol";
import {TickLib} from "../../src/libraries/TickLib.sol";
import {UtilsLib} from "../../src/libraries/UtilsLib.sol";
import {Obligation, Offer} from "../../src/interfaces/IMorphoV2.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";
import {FEE_STEP} from "../../src/libraries/ConstantsLib.sol";

contract MorphoV2Harness is MorphoV2 {
    function getOfferPrice(uint256 tick) external pure returns (uint256) {
        return TickLib.tickToPrice(tick);
    }

    function getDefaultFee(address loanToken, uint256 index) external view returns (uint256) {
        return uint256(defaultFees[loanToken][index]) * FEE_STEP;
    }

    /// @dev Returns the trading fee rate that `take` would use for the given offer at the current block.
    function computeTradingFeeForOffer(Offer memory offer) external view returns (uint256) {
        bytes20 id = IdLib.toId(offer.obligation, block.chainid, address(this));
        uint256 timeToMaturity = UtilsLib.zeroFloorSub(offer.obligation.maturity, block.timestamp);
        return tradingFee(id, timeToMaturity);
    }

    function getCollateralPrice(Obligation memory obligation, uint256 collateralIndex) external view returns (uint256) {
        return IOracle(obligation.collaterals[collateralIndex].oracle).price();
    }

    function getCollateralToken(Obligation memory obligation, uint256 collateralIndex) external pure returns (address) {
        return obligation.collaterals[collateralIndex].token;
    }

    function getCollateralsLength(Obligation memory obligation) external pure returns (uint256) {
        return obligation.collaterals.length;
    }

}
