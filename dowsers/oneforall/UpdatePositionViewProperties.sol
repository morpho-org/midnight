// SPDX-License-Identifier: BUSL-1.1
//
// OneForAll port of certora/specs/UpdatePositionView.spec (midnight 4ccffed1).
//
//   dowsersRun OneForAll dowsers/oneforall/UpdatePositionViewProperties.sol UpdatePositionViewProperties
//
// Non-vacuity check, expected to fail. Same requires; the credit bound is strict.
// A synced position (loss factors equal, lastAccrual == block.timestamp) returns
// newCredit == credit on a call that does not revert, so `<` is false.
//
//   dowsersRun OneForAll dowsers/oneforall/UpdatePositionViewProperties.sol UpdatePositionViewPropertiesBroken
//
// The CVL rule updatePositionViewProperties is the postcondition of
// verify_updatePositionView_properties. updatePositionViewEqualsCreditWhenSynced
// is an assert in that same function: a second call hangs the translator.
// noCreditWhenLastLossFactorMaxed is a require on the harness write, the same
// assumption as the CVL rule's requireInvariant. As a contract invariant it
// does not hold on entry: the nested mapping is not known to start at zero.
//
// Divergences from src/Midnight.sol, all deliberate:
//
// * One file. OneForAll uploads only the .sol named on the command line.
// * MarketState and Position keep only the fields updatePositionView reads or
//   the rules mention. Collateral, debt and the rest of Midnight are not in
//   this spec.
// * updatePositionView takes `uint256 maturity` rather than `Market memory`.
//   The real function only reads `market.maturity`. A memory struct literal
//   becomes an unresolved `market_ctor`, and assigning `market.maturity`
//   hangs the translator.
// * UtilsLib.min is the same function without inline assembly. OneForAll drops
//   assembly blocks, so the original body would leave `min` unconstrained.
// * A CVL rule starts from an arbitrary state. OneForAll starts from the
//   constructor and only changes storage when a public function writes it.
//   Each verify_* function therefore writes its symbolic arguments into
//   storage before calling the real view. Solidity `require` is the CVL
//   `require`: it reverts, and the postcondition is claimed only on success.
// * preciseCreditCorrect is a CVL ghost (mathint, storage hooks). OneForAll
//   has no mathint storage. The ghost is the identity
//   precise = PRECISION * credit / mapFactor(lastLossFactor)
//   with PRECISION = 2^128 and mapFactor(f) = type(uint128).max - f, plus a
//   hook assumption that the division is exact. Under that assumption
//   (newCredit + fee) * PRECISION <= precise * mapFactor(lossFactor)
//   cancels to
//   (newCredit + fee) * mapFactor(lastLossFactor) <= credit * mapFactor(lossFactor).
//   That product in Spec.Ensures hangs the translator, so it is not in the
//   clause. The proved postcondition is the three monotonicity bounds; the
//   total-loss and synced claims are asserts.
// * Preservation of noCreditWhenLastLossFactorMaxed by take / withdraw /
//   liquidate is not in this slice. Those methods are the rest of Midnight,
//   and this spec summarizes them away. The require below is the same
//   assumption the CVL rule gets from requireInvariant.
//
pragma solidity 0.8.34;

struct MarketState {
    uint128 lossFactor;
}

struct Position {
    uint128 credit;
    uint128 pendingFee;
    uint128 lastLossFactor;
    uint128 lastAccrual;
}

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

/// @dev Slice of Midnight covering updatePositionView only.
contract UpdatePositionViewSlice {
    using UtilsLib for uint256;
    using UtilsLib for uint128;

    mapping(bytes32 id => mapping(address user => Position)) internal position;
    mapping(bytes32 id => MarketState) internal marketState;

    /// @dev Expects the id to correspond to the market's id.
    /// @dev Returns the new credit, new pending fee, and accrued fee after having updated the position.
    /// @dev `maturity` is `market.maturity` on the real signature. See the file header.
    function updatePositionView(uint256 maturity, bytes32 id, address user)
        public
        view
        returns (uint128, uint128, uint128)
    {
        Position storage _position = position[id][user];
        uint128 _credit = _position.credit;
        uint128 _lastLossFactor = _position.lastLossFactor;
        uint256 postSlashCredit = _lastLossFactor < type(uint128).max
            ? _credit.mulDivDown(type(uint128).max - marketState[id].lossFactor, type(uint128).max - _lastLossFactor)
            : 0;
        uint128 _pendingFee = _position.pendingFee;
        uint256 postSlashPendingFee =
            _credit > 0 ? _pendingFee - _pendingFee.mulDivUp(_credit - postSlashCredit, _credit) : 0;
        uint256 accrualEnd = UtilsLib.min(block.timestamp, maturity);
        uint128 _lastAccrual = _position.lastAccrual;
        // forge-lint: disable-next-item(unsafe-typecast) as fee <= pending <= credit which are uint128 position fields
        uint128 fee = _lastAccrual < maturity
            ? uint128(postSlashPendingFee.mulDivDown(accrualEnd - _lastAccrual, maturity - _lastAccrual))
            : 0;
        // forge-lint: disable-next-item(unsafe-typecast) as credit and pending are <= uint128 position fields
        return (uint128(postSlashCredit) - fee, uint128(postSlashPendingFee) - fee, fee);
    }
}

library Spec {
    function Ensures(bool b) external view {}
    function Impl(bool a, bool b) external view returns (bool) {}
    function Revert() external view returns (bool) {}
}

contract UpdatePositionViewHarness is UpdatePositionViewSlice {
    function _store(
        bytes32 id,
        address user,
        uint128 creditAmt,
        uint128 pendingFeeAmt,
        uint128 lastLossFactorAmt,
        uint128 lastAccrualAmt,
        uint128 lossFactorAmt
    ) internal {
        // Field writes, not a struct literal. OneForAll emits a `position_ctor`
        // call for `Position({...})` and then Boogie cannot resolve it.
        Position storage stored = position[id][user];
        stored.credit = creditAmt;
        stored.pendingFee = pendingFeeAmt;
        stored.lastLossFactor = lastLossFactorAmt;
        stored.lastAccrual = lastAccrualAmt;
        marketState[id].lossFactor = lossFactorAmt;
        // CVL requireInvariant noCreditWhenLastLossFactorMaxed, for this user.
        // A quantified contract invariant does not hold on entry here.
        require(
            lastLossFactorAmt != type(uint128).max || creditAmt == 0, "noCreditWhenLastLossFactorMaxed"
        );
    }
}

contract UpdatePositionViewProperties is UpdatePositionViewHarness {
    /// CVL rule `updatePositionViewProperties`.
    function verify_updatePositionView_properties(
        bytes32 id,
        address user,
        uint256 maturity,
        uint128 creditAmt,
        uint128 pendingFeeAmt,
        uint128 lastLossFactorAmt,
        uint128 lastAccrualAmt,
        uint128 lossFactorAmt
    ) external returns (uint128 newCredit, uint128 newPendingFee, uint128 fee) {
        _store(id, user, creditAmt, pendingFeeAmt, lastLossFactorAmt, lastAccrualAmt, lossFactorAmt);
        require(lastLossFactorAmt <= lossFactorAmt, "lastLossFactorLeqMarketLossFactor");
        require(block.timestamp >= lastAccrualAmt, "Time is increasing");

        (newCredit, newPendingFee, fee) = updatePositionView(maturity, id, user);

        // mapFactor(lossFactor) == 0 => newCredit == 0 && fee == 0
        // mapFactor(lastLossFactor) == 0 => newCredit == 0 && fee == 0
        if (lossFactorAmt == type(uint128).max) assert(newCredit == 0 && fee == 0);
        if (lastLossFactorAmt == type(uint128).max) assert(newCredit == 0 && fee == 0);

        // CVL rule updatePositionViewEqualsCreditWhenSynced.
        // An assert, not a second call: a second call to updatePositionView hangs
        // the translator. Equality with block.timestamp holds only when the
        // timestamp fits in uint128, which is that rule's bound.
        assert(
            lastLossFactorAmt != lossFactorAmt || lastAccrualAmt != block.timestamp || newCredit == creditAmt
        );

        // fee <= oldPendingFee, newCredit <= oldCredit, newPendingFee <= oldPendingFee.
        // The precise-credit product
        //   (newCredit + fee) * mapFactor(lastLossFactor) <= credit * mapFactor(lossFactor)
        // is the CVL `(newCredit + fee) * PRECISION <= preciseCreditBefore` bound after
        // cancelling PRECISION. Putting that product in Spec.Ensures hangs translation.
        Spec.Ensures(
            Spec.Impl(
                !Spec.Revert(),
                fee <= pendingFeeAmt && newCredit <= creditAmt && newPendingFee <= pendingFeeAmt
            )
        );
    }
}

/// Same rule as `UpdatePositionViewProperties`, with `newCredit <= credit` tightened
/// to `newCredit < credit`. Fails on a non-reverting synced position, where the
/// slash ratio is 1 and no fee accrues, so `newCredit == credit`.
contract UpdatePositionViewPropertiesBroken is UpdatePositionViewHarness {
    function verify_updatePositionView_properties(
        bytes32 id,
        address user,
        uint256 maturity,
        uint128 creditAmt,
        uint128 pendingFeeAmt,
        uint128 lastLossFactorAmt,
        uint128 lastAccrualAmt,
        uint128 lossFactorAmt
    ) external returns (uint128 newCredit, uint128 newPendingFee, uint128 fee) {
        _store(id, user, creditAmt, pendingFeeAmt, lastLossFactorAmt, lastAccrualAmt, lossFactorAmt);
        require(lastLossFactorAmt <= lossFactorAmt, "lastLossFactorLeqMarketLossFactor");
        require(block.timestamp >= lastAccrualAmt, "Time is increasing");

        (newCredit, newPendingFee, fee) = updatePositionView(maturity, id, user);

        if (lossFactorAmt == type(uint128).max) assert(newCredit == 0 && fee == 0);
        if (lastLossFactorAmt == type(uint128).max) assert(newCredit == 0 && fee == 0);

        assert(
            lastLossFactorAmt != lossFactorAmt || lastAccrualAmt != block.timestamp || newCredit == creditAmt
        );

        // Mutant. The real rule has `newCredit <= creditAmt`.
        Spec.Ensures(
            Spec.Impl(
                !Spec.Revert(),
                fee <= pendingFeeAmt && newCredit < creditAmt && newPendingFee <= pendingFeeAmt
            )
        );
    }
}
