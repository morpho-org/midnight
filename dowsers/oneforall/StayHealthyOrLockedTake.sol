// SPDX-License-Identifier: BUSL-1.1
//
// OneForAll port of certora/specs/Healthiness.spec rule stayHealthyOrLocked,
// instantiated on Midnight.take.
//
//   dowsersRun OneForAll dowsers/oneforall/StayHealthyOrLockedTake.sol StayHealthyOrLockedTakeProperties
//
// The CVL rule is verify_stayHealthyOrLocked_take. For take, the rule sets
// useIsHealthyNoBitmap to false, so the predicate is isHealthy || liquidationLocked.
//
// Divergences from src/Midnight.sol, all deliberate:
//
// * One file. OneForAll uploads only the .sol named on the command line.
// * Offer and Market are scalars. A memory struct literal becomes an
//   unresolved *_ctor. id, buy, maker, taker, units and maturity are the
//   fields the debt update and the health check read.
// * The tracked borrower is the CVL globalBorrower, and this take is on that
//   borrower's market. A take on any other market does not write the tracked
//   position. That case is omitted. Callbacks are summarized in CVL to
//   require the same predicate on the way out, so they are not a second
//   write either.
// * Authorization, the ratifier, offer caps, the consumed counter, tick
//   spacing, settlement fee, continuous fee, pending fee, reduce-only and
//   the enter gate are omitted. They revert, or they do not change debt or
//   collateral. The ratifier and the enter gate run before the debt write,
//   so their pre-callback health check is the precondition.
// * _updatePosition is omitted. It changes credit and pending fee, not debt
//   or collateral, and take calls it twice, which hangs the translator. The
//   stored credit is the credit the trade uses. A loss-factor slash only
//   reduces credit, which can only increase the seller's new debt. The
//   seller is locked before the callback check, and SellerIsLiquidatable
//   reverts afterwards unless the seller is healthy or still locked, so a
//   larger debt increase does not add a health obligation.
// * Collateral is two slots. Healthiness.spec axioms
//   globalMarketCollateralLength <= 2. isHealthy walks those bits instead of
//   UtilsLib.msb / clearBit, which are assembly. OneForAll drops assembly.
//   Higher bits are rejected in the harness. Oracle price() is the CVL
//   summaryPrice ghost: a uint256 argument, constant for the call.
// * Position is not a struct, and take does not hold a storage reference.
//   OneForAll treats `position[id][seller]` and `position[id][borrower]` as
//   the same slot: the counterexample has three distinct addresses, borrower
//   debt 0 (so the precondition holds), and after the seller debt write the
//   borrower's debt is positive with neither collateral bit set. Each field
//   is its own mapping. The trade reads buyer and seller into locals, then
//   writes those locals back.
// * The liquidation lock is a bool mapping. Midnight stores it in transient
//   storage with tload / tstore.
// * onBuy, the two loan-token transfers and onSell are the CVL genericCallback.
//   That summary checks the predicate, havocs, requires the lock unchanged
//   and requires the predicate again. The slice checks the predicate while
//   the seller is locked, then restores the lock. It does not havoc: the
//   post-callback require is the summary's assumption, and the only later
//   write is clearing the lock.
// * SellerIsLiquidatable is kept when the seller is the tracked borrower.
//   When the seller is someone else the require only reverts and does not
//   write the tracked position, and this slice has no collateral for that
//   seller. Those reverts are omitted.
// * The CVL `require forall axiomMathMulDivDownMonotoneA` is mulDivDown
//   itself. The function here is (x * y) / d.
// * The CVL asserts are bools. They stay `assert`s. A product in Spec.Ensures
//   hangs the translator, and Solidity 0.8 reverts if a health product
//   overflows uint256, so those traces are excluded. take is called once.
//
pragma solidity 0.8.34;

uint256 constant WAD = 1e18;
uint256 constant ORACLE_PRICE_SCALE = 1e36;

library UtilsLib {
    /// @dev Same result as Midnight's assembly `min`. Written in Solidity
    /// because OneForAll emits nothing for an `assembly` block.
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    /// @dev Same result as Midnight's assembly `zeroFloorSub`.
    function zeroFloorSub(uint256 x, uint256 y) internal pure returns (uint256) {
        return x > y ? x - y : 0;
    }

    /// @dev Returns (x * y) / d rounded down.
    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y) / d;
    }

    function toUint128(uint256 x) internal pure returns (uint128) {
        require(x <= type(uint128).max, "CastOverflow");
        return uint128(x);
    }
}

/// @dev Slice of Midnight.take covering the debt update, the seller lock, and isHealthy.
contract StayHealthyOrLockedTakeSlice {
    using UtilsLib for uint256;

    // Separate maps, not a Position struct. A storage reference into a map of
    // structs aliases distinct addresses. See the file header.
    mapping(bytes32 id => mapping(address user => uint128)) internal credit;
    mapping(bytes32 id => mapping(address user => uint128)) internal debt;
    mapping(bytes32 id => mapping(address user => uint128)) internal collateralBitmap;
    mapping(bytes32 id => mapping(address user => uint128)) internal collateral0;
    mapping(bytes32 id => mapping(address user => uint128)) internal collateral1;
    mapping(bytes32 id => mapping(address user => bool)) internal liquidationLocked;

    uint256 internal maturity;
    uint256 internal price0;
    uint256 internal price1;
    uint256 internal lltv0;
    uint256 internal lltv1;

    /// @dev Bitmap form of Midnight.isHealthy, unrolled for two collaterals.
    /// Debt 0 is healthy without reading the bitmap, as in Midnight.
    function isHealthy(bytes32 id, address borrower) public view returns (bool) {
        uint256 debtAmt = debt[id][borrower];
        uint256 maxDebt;
        if (debtAmt > 0) {
            uint256 bitmap = collateralBitmap[id][borrower];
            if ((bitmap & 1) != 0) {
                maxDebt += uint256(collateral0[id][borrower]).mulDivDown(price0, ORACLE_PRICE_SCALE).mulDivDown(lltv0, WAD);
            }
            if ((bitmap & 2) != 0) {
                maxDebt += uint256(collateral1[id][borrower]).mulDivDown(price1, ORACLE_PRICE_SCALE).mulDivDown(lltv1, WAD);
            }
        }
        return maxDebt >= debtAmt;
    }

    /// @dev `borrower` is the CVL globalBorrower. Buyer and seller are maker and taker, swapped by `buy`.
    function take(bytes32 id, address borrower, bool buy, address maker, address taker, uint256 units)
        public
        returns (bool healthyOrLockedBeforeCallbacks, bool healthyOrLockedAfter)
    {
        require(maker != taker, "SelfTake");
        require(isHealthy(id, borrower) || liquidationLocked[id][borrower], "user is healthy or locked before call");

        address buyer = buy ? maker : taker;
        address seller = buy ? taker : maker;
        uint256 buyerDebt = debt[id][buyer];
        uint256 buyerCredit = credit[id][buyer];
        uint256 sellerDebt = debt[id][seller];
        uint256 sellerCredit = credit[id][seller];

        uint256 buyerCreditIncrease = UtilsLib.zeroFloorSub(units, buyerDebt);
        uint256 sellerCreditDecrease = UtilsLib.min(units, sellerCredit);
        uint256 sellerDebtIncrease = units - sellerCreditDecrease;

        require(block.timestamp <= maturity || sellerDebtIncrease == 0, "CannotIncreaseDebtPostMaturity");

        debt[id][buyer] = UtilsLib.toUint128(buyerDebt - (units - buyerCreditIncrease));
        credit[id][buyer] = UtilsLib.toUint128(buyerCredit + buyerCreditIncrease);
        credit[id][seller] = UtilsLib.toUint128(sellerCredit - sellerCreditDecrease);
        debt[id][seller] = UtilsLib.toUint128(sellerDebt + sellerDebtIncrease);

        // Lock the seller, then check. Transfers always run, so the CVL
        // callback observes this lock. isHealthy does not read the lock, so
        // the value computed after the debt write is the one both checks use.
        bool healthy = isHealthy(id, borrower);
        bool wasLocked = liquidationLocked[id][seller];
        liquidationLocked[id][seller] = true;
        healthyOrLockedBeforeCallbacks = healthy || liquidationLocked[id][borrower];

        if (!wasLocked) liquidationLocked[id][seller] = false;
        if (seller == borrower) {
            require(liquidationLocked[id][borrower] || healthy, "SellerIsLiquidatable");
        }

        healthyOrLockedAfter = healthy || liquidationLocked[id][borrower];
    }
}

contract StayHealthyOrLockedTakeProperties is StayHealthyOrLockedTakeSlice {
    function _write(
        bytes32 id,
        address user,
        uint128 creditAmt,
        uint128 debtAmt,
        uint128 bitmapAmt,
        uint128 collateral0Amt,
        uint128 collateral1Amt,
        bool lockedAmt
    ) internal {
        credit[id][user] = creditAmt;
        debt[id][user] = debtAmt;
        collateralBitmap[id][user] = bitmapAmt;
        collateral0[id][user] = collateral0Amt;
        collateral1[id][user] = collateral1Amt;
        liquidationLocked[id][user] = lockedAmt;
    }

    /// CVL rule `stayHealthyOrLocked` for `take`.
    /// Maker and taker debt/credit are used only when that address is not the borrower.
    /// The borrower's arguments are the position when the addresses coincide.
    function verify_stayHealthyOrLocked_take(
        bytes32 id,
        address borrower,
        address maker,
        address taker,
        bool buy,
        uint256 units,
        uint256 maturityAmt,
        uint256 price0Amt,
        uint256 price1Amt,
        uint256 lltv0Amt,
        uint256 lltv1Amt,
        uint128 borrowerDebt,
        uint128 borrowerCredit,
        uint128 borrowerCollateral0,
        uint128 borrowerCollateral1,
        uint128 borrowerBitmap,
        bool borrowerLocked,
        uint128 makerDebt,
        uint128 makerCredit,
        uint128 takerDebt,
        uint128 takerCredit
    ) external returns (bool healthyOrLockedBeforeCallbacks, bool healthyOrLockedAfter) {
        maturity = maturityAmt;
        price0 = price0Amt;
        price1 = price1Amt;
        lltv0 = lltv0Amt;
        lltv1 = lltv1Amt;
        require(borrowerBitmap < 4, "globalMarketCollateralLength <= 2");

        _write(
            id,
            borrower,
            borrowerCredit,
            borrowerDebt,
            borrowerBitmap,
            borrowerCollateral0,
            borrowerCollateral1,
            borrowerLocked
        );
        if (maker != borrower) _write(id, maker, makerCredit, makerDebt, 0, 0, 0, false);
        if (taker != borrower && taker != maker) _write(id, taker, takerCredit, takerDebt, 0, 0, 0, false);

        (healthyOrLockedBeforeCallbacks, healthyOrLockedAfter) =
            take(id, borrower, buy, maker, taker, units);

        assert(healthyOrLockedBeforeCallbacks);
        assert(healthyOrLockedAfter);
    }
}
