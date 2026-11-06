// SPDX-License-Identifier: BUSL-1.1
//
// OneForAll port of certora/specs/LiquidationBoundedByLIF.spec.
//
//   dowsersRun OneForAll dowsers/oneforall/LiquidationBoundedByLIF.sol LiquidationBoundedByLIFProperties
//
// The CVL rules liquidationProfitBoundedInputRepaidUnits and
// liquidationProfitBoundedSeizedAssets are
// verify_liquidationProfitBoundedInputRepaidUnits and
// verify_liquidationProfitBoundedSeizedAssets.
//
// Divergences from src/Midnight.sol, all deliberate:
//
// * One file. OneForAll uploads only the .sol named on the command line.
// * The bitmap walk, bad-debt socialization, recovery close factor, liquidator
//   gate, liquidation lock, health check, callback and token transfers are not
//   in this slice. They either revert or run after the returned amounts are
//   fixed. The CVL spec summarizes transfers as NONDET and requires
//   data.length == 0, so the callback is already out of the rules.
// * liquidatedCollatPrice is the `price` argument. In Midnight it is the
//   oracle price when collateralIndex is set in the bitmap, and 0 otherwise.
//   The seized-assets rule's requireInvariant nonZeroCollateralsAreActivated
//   is what makes that price the oracle price of a non-zero collateral. Here
//   the assertion uses the same `price` the formula uses, so that invariant
//   is the interpretation of the argument rather than a second fact.
// * A Market memory argument becomes an unresolved market_ctor. lltv,
//   liquidationCursor and maturity are scalars. maxLif is computed once in
//   the harness and passed in: a second call of the sliced function hangs
//   the translator, and maxLif is the value the CVL rule names in the assert.
// * UtilsLib.min is the same function without inline assembly. OneForAll
//   drops assembly blocks, so the original body would leave min unconstrained.
// * The CVL assert is mathint. The product is an `assert`, not a Spec.Ensures
//   clause: a product in Spec.Ensures hangs the translator. Solidity 0.8
//   reverts if the product overflows uint256, so those traces are excluded.
// * Post-maturity still requires block.timestamp > maturity before the LIF
//   interpolation, which is Midnight's NotLiquidatable check for that mode.
//   The pre-maturity half of that check (debt > maxDebt) does not change the
//   returned amounts.
//
pragma solidity 0.8.34;

uint256 constant WAD = 1e18;
uint256 constant ORACLE_PRICE_SCALE = 1e36;
uint256 constant TIME_TO_MAX_LIF = 60 minutes;

library UtilsLib {
    /// @dev Same result as Midnight's assembly `min`. Written in Solidity
    /// because OneForAll emits nothing for an `assembly` block.
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    /// @dev Returns (x * y) / d rounded down.
    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y) / d;
    }

    /// @dev Returns (x * y) / d rounded up.
    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }
}

/// @dev Midnight's maxLif. Reverts when the denominator is 0, as mulDivDown does.
function maxLif(uint256 lltv, uint256 liquidationCursor) pure returns (uint256) {
    return UtilsLib.mulDivDown(WAD, WAD, WAD - UtilsLib.mulDivDown(liquidationCursor, WAD - lltv, WAD));
}

/// @dev Slice of Midnight.liquidate covering the seized/repaid conversion only.
contract LiquidationBoundedByLIFSlice {
    using UtilsLib for uint256;

    /// @dev `maxLifAmt` is maxLif(lltv, liquidationCursor), computed by the harness.
    /// @dev `price` is liquidatedCollatPrice.
    function liquidate(
        uint256 maturity,
        uint256 price,
        uint256 maxLifAmt,
        uint256 seizedAssets,
        uint256 repaidUnits,
        bool postMaturityMode
    ) public view returns (uint256, uint256) {
        require(repaidUnits == 0 || seizedAssets == 0, "InconsistentInput");
        require(maxLifAmt >= WAD, "maxLif must be at least 1x");
        // NotLiquidatable, post-maturity half. The subtraction below is the real formula.
        require(!postMaturityMode || block.timestamp > maturity, "NotLiquidatable");

        uint256 lif = postMaturityMode
            ? UtilsLib.min(maxLifAmt, WAD + (maxLifAmt - WAD) * (block.timestamp - maturity) / TIME_TO_MAX_LIF)
            : maxLifAmt;

        if (seizedAssets > 0) {
            repaidUnits = seizedAssets.mulDivUp(price, ORACLE_PRICE_SCALE).mulDivUp(WAD, lif);
        } else if (repaidUnits > 0) {
            seizedAssets = repaidUnits.mulDivDown(lif, WAD).mulDivDown(ORACLE_PRICE_SCALE, price);
        }
        return (seizedAssets, repaidUnits);
    }
}

contract LiquidationBoundedByLIFProperties is LiquidationBoundedByLIFSlice {
    /// CVL rule `liquidationProfitBoundedInputRepaidUnits`. seizedAssets input is 0.
    function verify_liquidationProfitBoundedInputRepaidUnits(
        uint256 lltv,
        uint256 liquidationCursor,
        uint256 maturity,
        uint256 price,
        uint256 repaidUnits,
        bool postMaturityMode
    ) external returns (uint256 seizedResult, uint256 repaidResult) {
        uint256 maxLifAmt = maxLif(lltv, liquidationCursor);
        require(maxLifAmt >= WAD, "maxLif must be at least 1x for profit boundedness");

        (seizedResult, repaidResult) = liquidate(maturity, price, maxLifAmt, 0, repaidUnits, postMaturityMode);

        // seized * price * WAD <= repaid * ORACLE_PRICE_SCALE * maxLif
        assert(seizedResult * price * WAD <= repaidResult * ORACLE_PRICE_SCALE * maxLifAmt);
    }

    /// CVL rule `liquidationProfitBoundedSeizedAssets`. repaidUnits input is 0.
    function verify_liquidationProfitBoundedSeizedAssets(
        uint256 lltv,
        uint256 liquidationCursor,
        uint256 maturity,
        uint256 price,
        uint256 seizedAssets,
        bool postMaturityMode
    ) external returns (uint256 seizedResult, uint256 repaidResult) {
        uint256 maxLifAmt = maxLif(lltv, liquidationCursor);
        require(maxLifAmt >= WAD, "maxLif must be at least 1x for profit boundedness");

        (seizedResult, repaidResult) = liquidate(maturity, price, maxLifAmt, seizedAssets, 0, postMaturityMode);

        assert(seizedResult * price * WAD <= repaidResult * ORACLE_PRICE_SCALE * maxLifAmt);
    }
}
