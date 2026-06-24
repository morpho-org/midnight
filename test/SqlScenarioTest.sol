// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test, Vm} from "../lib/forge-std/src/Test.sol";
import {BaseTest, LLTV_5} from "./BaseTest.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {WAD, ORACLE_PRICE_SCALE, LIQUIDATION_CURSOR_LOW, maxLif as _maxLif} from "../src/libraries/ConstantsLib.sol";
import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";
import {Signature} from "../src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {HashLib} from "../src/ratifiers/libraries/HashLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

/// @dev Generates a randomised scenario covering all Midnight event types, including liquidation.
/// Writes event tables (JSON arrays) and expected on-chain state to sql/test/events/.
///
/// Block layout
/// ─────────────────────────────────────────────────────────────────────────────
/// Block  1: setUp events (Constructor, SetFeeSetter, SetTickSpacingSetter,
///            SetIsAuthorized ×4, SetFeeClaimer)
/// Block  2: SetDefaultSettlementFee (index 3, 100 CBP)
/// Block  3: SetDefaultContinuousFee
/// Block  4: SupplyCollateral → MarketCreated + SupplyCollateral  (borrower)
/// Block  5: Take #1  (lender buy offer, borrower takes)
/// Block  6: SupplyCollateral (otherBorrower, liquidation victim)
/// Block  7: Take #2  (otherLender buy offer, otherBorrower takes)
/// Block  8: Repay partial (borrower)
/// Block  9: WithdrawCollateral (borrower)
/// Block 10: UpdatePosition (lender, explicit)
/// Block 11: SetMarketSettlementFee (index 3 → 50 CBP)
/// Block 12: SetMarketContinuousFee
/// Block 13: UpdatePosition (large time-warp → continuousFee accrues)
/// Block 14: SetIsAuthorized (lender → otherLender)
/// Block 15: SetConsumed (borrower, cancel GROUP_A)
/// Block 16: Liquidate (oracle drop → liquidate otherBorrower → restore price)
/// Block 17: Withdraw (lender)
/// Block 18: ClaimSettlementFee
/// Block 19: ClaimContinuousFee
///
/// Run with:  forge test --match-test testGenerateScenario -vv
/// Verify:    python3 sql/test/verify.py
contract SqlScenarioTest is BaseTest {
    using UtilsLib for uint256;

    // ── Scenario parameters
    // ──────────────────────────────────────────────────
    // Settlement fees must be multiples of CBP (1e12).
    uint256 internal constant DEFAULT_SETTLEMENT_FEE_RAW = 100 * 1_000_000_000_000;
    uint256 internal constant MARKET_SETTLEMENT_FEE_RAW = 50 * 1_000_000_000_000;
    bytes32 internal constant GROUP_A = keccak256("group-a");
    bytes32 internal constant GROUP_B = keccak256("group-b");

    // ── Market
    // ───────────────────────────────────────────────────────────────
    Market internal market;
    bytes32 internal id;

    // ── Event type selectors
    // ─────────────────────────────────────────────────
    bytes32 internal constant SEL_TAKE = keccak256(
        "Take(bytes32,bytes32,bool,address,bytes32,address,bytes,uint256,address,address,uint256,uint256,uint256,uint256,uint256,address,address)"
    );
    bytes32 internal constant SEL_UPDATE_POS = keccak256("UpdatePosition(bytes32,address,uint256,uint256,uint256)");
    bytes32 internal constant SEL_WITHDRAW = keccak256("Withdraw(address,bytes32,uint256,address,address,uint256)");
    bytes32 internal constant SEL_REPAY = keccak256("Repay(address,bytes32,uint256,address,address)");
    bytes32 internal constant SEL_SUPPLY_COL = keccak256("SupplyCollateral(address,bytes32,address,uint256,address)");
    bytes32 internal constant SEL_WITHDRAW_COL =
        keccak256("WithdrawCollateral(address,bytes32,address,uint256,address,address)");
    bytes32 internal constant SEL_MARKET_CREATED = keccak256(
        "MarketCreated((uint256,address,address,(address,uint256,uint256,address)[],uint256,uint256,address,address),bytes32)"
    );
    bytes32 internal constant SEL_SET_CONSUMED = keccak256("SetConsumed(address,bytes32,uint256,address)");
    bytes32 internal constant SEL_SET_IS_AUTH = keccak256("SetIsAuthorized(address,address,bool,address)");
    bytes32 internal constant SEL_SET_DEF_TF = keccak256("SetDefaultSettlementFee(address,uint256,uint256)");
    bytes32 internal constant SEL_SET_MKT_TF = keccak256("SetMarketSettlementFee(bytes32,uint256,uint256)");
    bytes32 internal constant SEL_SET_MKT_CF = keccak256("SetMarketContinuousFee(bytes32,uint256)");
    bytes32 internal constant SEL_CLAIM_TF = keccak256("ClaimSettlementFee(address,address,uint256,address)");
    bytes32 internal constant SEL_CLAIM_CF = keccak256("ClaimContinuousFee(address,bytes32,uint256,address)");
    bytes32 internal constant SEL_CONSTRUCTOR = keccak256("Constructor(address)");
    bytes32 internal constant SEL_SET_FEE_SETTER = keccak256("SetFeeSetter(address)");
    bytes32 internal constant SEL_SET_FEE_CLAIMER = keccak256("SetFeeClaimer(address)");
    bytes32 internal constant SEL_SET_TS_SETTER = keccak256("SetTickSpacingSetter(address)");
    bytes32 internal constant SEL_SET_DEF_CF = keccak256("SetDefaultContinuousFee(address,uint256)");
    bytes32 internal constant SEL_LIQUIDATE = keccak256(
        "Liquidate(address,bytes32,address,uint256,uint256,address,bool,address,address,uint256,uint256,uint256)"
    );

    // ── Per-event JSON accumulators
    // ───────────────────────────────────────────
    string internal jTake;
    string internal jUpdatePos;
    string internal jWithdraw;
    string internal jRepay;
    string internal jSupplyCol;
    string internal jWithdrawCol;
    string internal jMarketCreated;
    string internal jSetConsumed;
    string internal jSetIsAuth;
    string internal jSetDefTf;
    string internal jSetMktTf;
    string internal jSetMktCf;
    string internal jClaimTf;
    string internal jClaimCf;
    string internal jConstructor;
    string internal jSetFeeSetter;
    string internal jSetFeeClaimer;
    string internal jSetTsSetter;
    string internal jSetDefCf;
    string internal jLiquidate;

    uint256 internal logIdx;
    uint256 internal currentBlockTimestamp;

    // ── Setup
    // ─────────────────────────────────────────────────────────────────

    function setUp() public override {
        vm.warp(1000);
        vm.roll(1);
        super.setUp();
        midnight.setFeeClaimer(address(this));

        CollateralParams[] memory params = new CollateralParams[](1);
        params[0] = CollateralParams({
            token: address(collateralToken1),
            lltv: LLTV_5,
            maxLif: _maxLif(LLTV_5, LIQUIDATION_CURSOR_LOW),
            oracle: address(oracle1)
        });
        market = Market({
            chainId: block.chainid,
            midnight: address(midnight),
            loanToken: address(loanToken),
            collateralParams: params,
            maturity: 1000 + 30 days,
            rcfThreshold: 1,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
        oracle1.setPrice(ORACLE_PRICE_SCALE);
        id = toId(market);

        jTake = "[";
        jUpdatePos = "[";
        jWithdraw = "[";
        jRepay = "[";
        jSupplyCol = "[";
        jWithdrawCol = "[";
        jMarketCreated = "[";
        jSetConsumed = "[";
        jSetIsAuth = "[";
        jSetDefTf = "[";
        jSetMktTf = "[";
        jSetMktCf = "[";
        jClaimTf = "[";
        jClaimCf = "[";
        jConstructor = "[";
        jSetFeeSetter = "[";
        jSetFeeClaimer = "[";
        jSetTsSetter = "[";
        jSetDefCf = "[";
        jLiquidate = "[";
        logIdx = 0;
    }

    // ── Main test
    // ─────────────────────────────────────────────────────────────

    function testGenerateScenario() public {
        // Randomise key amounts; bounds chosen so all operations succeed.
        uint256 units1 = vm.randomUint(300_000, 800_000); // borrower's debt
        uint256 repayFraction = vm.randomUint(20, 70); // % of units1 repaid
        uint256 withdrawCol = vm.randomUint(5, 50); // tokens withdrawn
        uint256 otherUnits = vm.randomUint(500, 2_000); // otherBorrower's debt (small for liquidation)

        // Block 2: SetDefaultSettlementFee (100 CBP at 30-day breakpoint)
        vm.roll(2);
        vm.warp(2000);
        _exec(abi.encodeCall(midnight.setDefaultSettlementFee, (address(loanToken), 3, DEFAULT_SETTLEMENT_FEE_RAW)));

        // Block 3: SetDefaultContinuousFee
        vm.roll(3);
        vm.warp(3000);
        _exec(abi.encodeCall(midnight.setDefaultContinuousFee, (address(loanToken), 50)));

        // Block 4: borrower supplies collateral → creates market
        vm.roll(4);
        vm.warp(4000);
        uint256 col1 = units1 * 12 / 10; // 120 % safety buffer over LLTV
        deal(address(collateralToken1), borrower, col1);
        vm.prank(borrower);
        collateralToken1.approve(address(midnight), col1);
        _execAs(borrower, abi.encodeWithSelector(midnight.supplyCollateral.selector, market, 0, col1, borrower));

        // Block 5: Take #1 — lender posts buy offer, borrower takes
        vm.roll(5);
        vm.warp(5000);
        deal(address(loanToken), lender, units1 * 2);
        Offer memory offer1;
        offer1.market = market;
        offer1.buy = true;
        offer1.maker = lender;
        offer1.maxUnits = units1;
        offer1.continuousFeeCap = type(uint256).max;
        offer1.group = GROUP_A;
        offer1.ratifier = address(ecrecoverRatifier);
        offer1.start = vm.getBlockTimestamp();
        offer1.expiry = vm.getBlockTimestamp() + 200;
        offer1.tick = MAX_TICK;
        bytes memory rd1 = merkleRatifierData([offer1]);
        _execAs(borrower, abi.encodeCall(midnight.take, (offer1, rd1, units1, borrower, borrower, address(0), hex"")));

        // Block 6: otherBorrower supplies collateral (liquidation victim setup)
        vm.roll(6);
        vm.warp(6000);
        // Exact minimum collateral at current oracle price
        uint256 col2 = otherUnits.mulDivUp(WAD, LLTV_5).mulDivUp(ORACLE_PRICE_SCALE, oracle1.price());
        deal(address(collateralToken1), otherBorrower, col2);
        vm.prank(otherBorrower);
        collateralToken1.approve(address(midnight), col2);
        _execAs(
            otherBorrower, abi.encodeWithSelector(midnight.supplyCollateral.selector, market, 0, col2, otherBorrower)
        );

        // Block 7: Take #2 — otherLender posts buy offer, otherBorrower takes
        vm.roll(7);
        vm.warp(7000);
        deal(address(loanToken), otherLender, otherUnits * 2);
        Offer memory offer2;
        offer2.market = market;
        offer2.buy = true;
        offer2.maker = otherLender;
        offer2.maxUnits = otherUnits;
        offer2.continuousFeeCap = type(uint256).max;
        offer2.group = GROUP_B;
        offer2.ratifier = address(ecrecoverRatifier);
        offer2.start = vm.getBlockTimestamp();
        offer2.expiry = vm.getBlockTimestamp() + 200;
        offer2.tick = MAX_TICK;
        bytes memory rd2 = merkleRatifierData([offer2]);
        _execAs(
            otherBorrower,
            abi.encodeCall(midnight.take, (offer2, rd2, otherUnits, otherBorrower, otherBorrower, address(0), hex""))
        );

        // Block 8: borrower repays partial debt
        vm.roll(8);
        vm.warp(8000);
        uint256 repayAmount = units1 * repayFraction / 100;
        deal(address(loanToken), borrower, repayAmount);
        _execAs(borrower, abi.encodeCall(midnight.repay, (market, repayAmount, borrower, address(0), hex"")));

        // Block 9: borrower withdraws some collateral
        vm.roll(9);
        vm.warp(9000);
        _execAs(
            borrower,
            abi.encodeWithSelector(midnight.withdrawCollateral.selector, market, 0, withdrawCol, borrower, borrower)
        );

        // Block 10: explicit updatePosition(lender)
        vm.roll(10);
        vm.warp(10000);
        _exec(abi.encodeCall(midnight.updatePosition, (market, lender)));

        // Block 11: setMarketSettlementFee (index 3 → 50 CBP)
        vm.roll(11);
        vm.warp(11000);
        _exec(abi.encodeCall(midnight.setMarketSettlementFee, (id, 3, MARKET_SETTLEMENT_FEE_RAW)));

        // Block 12: setMarketContinuousFee
        vm.roll(12);
        vm.warp(12000);
        _exec(abi.encodeCall(midnight.setMarketContinuousFee, (id, 80)));

        // Block 13: updatePosition with large time-warp → continuousFee accrues
        vm.roll(13);
        vm.warp(20000);
        _exec(abi.encodeCall(midnight.updatePosition, (market, lender)));

        // Block 14: setIsAuthorized (lender authorises otherLender)
        vm.roll(14);
        vm.warp(20100);
        _execAs(lender, abi.encodeWithSelector(midnight.setIsAuthorized.selector, otherLender, true, lender));

        // Block 15: setConsumed (borrower cancels GROUP_A)
        vm.roll(15);
        vm.warp(20200);
        _execAs(borrower, abi.encodeCall(midnight.setConsumed, (GROUP_A, 1_000_000_000_000_000_000, borrower)));

        // Block 16: liquidate otherBorrower (oracle drop → liquidation → restore)
        vm.roll(16);
        vm.warp(20300);
        oracle1.setPrice(ORACLE_PRICE_SCALE / 4); // 75 % price drop → position deeply underwater
        _exec(
            abi.encodeCall(
                midnight.liquidate, (market, 0, 0, 0, otherBorrower, false, address(this), address(0), hex"")
            )
        );
        oracle1.setPrice(ORACLE_PRICE_SCALE); // restore for subsequent operations

        // Block 17: lender withdraws — use at most half of available withdrawable
        vm.roll(17);
        vm.warp(20400);
        {
            (,, uint128 msW,,,,,,,,,,) = midnight.marketState(id);
            (uint128 lCr,,,,,) = midnight.position(id, lender);
            uint256 avail = msW < lCr ? uint256(msW) : uint256(lCr);
            uint256 withdrawUnits = avail / 2;
            if (withdrawUnits > 0) {
                _execAs(
                    lender, abi.encodeWithSelector(midnight.withdraw.selector, market, withdrawUnits, lender, lender)
                );
            }
        }

        // Block 18: claimSettlementFee
        vm.roll(18);
        vm.warp(20500);
        uint256 ctf = midnight.claimableSettlementFee(address(loanToken));
        if (ctf > 0) {
            _exec(abi.encodeCall(midnight.claimSettlementFee, (address(loanToken), ctf, address(this))));
        }

        // Block 19: claimContinuousFee
        vm.roll(19);
        vm.warp(20600);
        (,,, uint128 ms_cfc,,,,,,,,,) = midnight.marketState(id);
        if (ms_cfc > 0) {
            _exec(abi.encodeCall(midnight.claimContinuousFee, (market, ms_cfc, address(this))));
        }

        _appendSetUpEvents();
        _writeOutput();
    }

    // ── Execution helpers
    // ─────────────────────────────────────────────────────

    function _exec(bytes memory callData) internal {
        vm.recordLogs();
        uint256 bn = block.number;
        currentBlockTimestamp = block.timestamp;

        (bool ok, bytes memory ret) = address(midnight).call(callData);
        if (!ok) {
            assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        }

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            _processLog(logs[i], bn, logIdx++);
        }
    }

    function _execAs(address who, bytes memory callData) internal {
        vm.recordLogs();
        uint256 bn = block.number;
        currentBlockTimestamp = block.timestamp;

        vm.prank(who);
        (bool ok, bytes memory ret) = address(midnight).call(callData);
        if (!ok) {
            assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        }

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            _processLog(logs[i], bn, logIdx++);
        }
    }

    // ── Log dispatcher
    // ────────────────────────────────────────────────────────

    function _processLog(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        bytes32 sig = log.topics[0];
        if (sig == SEL_TAKE) _decodeTake(log, bn, idx);
        else if (sig == SEL_UPDATE_POS) _decodeUpdatePos(log, bn, idx);
        else if (sig == SEL_WITHDRAW) _decodeWithdraw(log, bn, idx);
        else if (sig == SEL_REPAY) _decodeRepay(log, bn, idx);
        else if (sig == SEL_SUPPLY_COL) _decodeSupplyCol(log, bn, idx);
        else if (sig == SEL_WITHDRAW_COL) _decodeWithdrawCol(log, bn, idx);
        else if (sig == SEL_MARKET_CREATED) _decodeMarketCreated(log, bn, idx);
        else if (sig == SEL_SET_CONSUMED) _decodeSetConsumed(log, bn, idx);
        else if (sig == SEL_SET_IS_AUTH) _decodeSetIsAuth(log, bn, idx);
        else if (sig == SEL_SET_DEF_TF) _decodeSetDefTf(log, bn, idx);
        else if (sig == SEL_SET_MKT_TF) _decodeSetMktTf(log, bn, idx);
        else if (sig == SEL_SET_MKT_CF) _decodeSetMktCf(log, bn, idx);
        else if (sig == SEL_CLAIM_TF) _decodeClaimTf(log, bn, idx);
        else if (sig == SEL_CLAIM_CF) _decodeClaimCf(log, bn, idx);
        else if (sig == SEL_CONSTRUCTOR) _decodeConstructor(log, bn, idx);
        else if (sig == SEL_SET_FEE_SETTER) _decodeSetFeeSetter(log, bn, idx);
        else if (sig == SEL_SET_FEE_CLAIMER) _decodeSetFeeClaimer(log, bn, idx);
        else if (sig == SEL_SET_TS_SETTER) _decodeSetTsSetter(log, bn, idx);
        else if (sig == SEL_SET_DEF_CF) _decodeSetDefCf(log, bn, idx);
        else if (sig == SEL_LIQUIDATE) _decodeLiquidate(log, bn, idx);
    }

    // ── Per-event decoders
    // ────────────────────────────────────────────────────

    function _decodeTake(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        bytes32 _id = log.topics[1];
        address maker = address(uint160(uint256(log.topics[2])));
        address taker = address(uint160(uint256(log.topics[3])));
        // data slots (0-indexed): 0=offerHash, 1=offerIsBuy, 2=group, 3=ratifier, 4=ratifierData(offset),
        // 5=units, 6=receiver, 7=buyerAssets, 8=sellerAssets, 9=consumed, 10=buyerPFI, 11=sellerPFD, 12=payer,
        // 13=caller
        bytes memory d = log.data;
        string memory body = string.concat(
            _sb("id_", _b32s(_id)),
            _c,
            _sb("maker", _as(maker)),
            _c,
            _sb("taker", _as(taker)),
            _c,
            _nb("offerisbuy", _word(d, 1) != 0 ? "true" : "false"),
            _c,
            _sn("buyerassets", uint256(_word(d, 7))),
            _c,
            _sn("sellerassets", uint256(_word(d, 8))),
            _c,
            _sn("units", uint256(_word(d, 5)))
        );
        body = string.concat(
            body,
            _c,
            _sb("group", _b32s(_word(d, 2))),
            _c,
            _sn("consumed", uint256(_word(d, 9))),
            _c,
            _sn("buyerpendingfeeincrease", uint256(_word(d, 10))),
            _c,
            _sn("sellerpendingfeedecrease", uint256(_word(d, 11)))
        );
        body = string.concat(body, _c, _sn("evt_block_number", bn), _c, _sn("evt_index", idx));
        jTake = _app(jTake, body);
    }

    function _decodeUpdatePos(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        bytes32 _id = log.topics[1];
        address user = address(uint160(uint256(log.topics[2])));
        (uint256 creditDecrease, uint256 pendingFeeDecrease, uint256 accruedFee) =
            abi.decode(log.data, (uint256, uint256, uint256));
        string memory body = string.concat(
            _sb("id_", _b32s(_id)),
            _c,
            _sb("user", _as(user)),
            _c,
            _sn("creditdecrease", creditDecrease),
            _c,
            _sn("pendingfeedecrease", pendingFeeDecrease),
            _c,
            _sn("accruedfee", accruedFee)
        );
        body = string.concat(
            body,
            _c,
            _sn("evt_block_time", currentBlockTimestamp),
            _c,
            _sn("evt_block_number", bn),
            _c,
            _sn("evt_index", idx)
        );
        jUpdatePos = _app(jUpdatePos, body);
    }

    function _decodeWithdraw(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        bytes32 _id = log.topics[1];
        address onB = address(uint160(uint256(log.topics[2])));
        address recv = address(uint160(uint256(log.topics[3])));
        (, uint256 units, uint256 pfd) = abi.decode(log.data, (address, uint256, uint256));
        jWithdraw = _app(
            jWithdraw,
            string.concat(
                _sb("id_", _b32s(_id)),
                _c,
                _sb("onbehalf", _as(onB)),
                _c,
                _sb("receiver", _as(recv)),
                _c,
                _sn("units", units),
                _c,
                _sn("pendingfeedecrease", pfd),
                _c,
                _sn("evt_block_number", bn),
                _c,
                _sn("evt_index", idx)
            )
        );
    }

    function _decodeRepay(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        bytes32 _id = log.topics[2];
        address onB = address(uint160(uint256(log.topics[3])));
        (uint256 units,) = abi.decode(log.data, (uint256, address));
        jRepay = _app(
            jRepay,
            string.concat(
                _sb("id_", _b32s(_id)),
                _c,
                _sb("onbehalf", _as(onB)),
                _c,
                _sn("units", units),
                _c,
                _sn("evt_block_number", bn),
                _c,
                _sn("evt_index", idx)
            )
        );
    }

    function _decodeSupplyCol(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        bytes32 _id = log.topics[1];
        address token = address(uint160(uint256(log.topics[2])));
        address onB = address(uint160(uint256(log.topics[3])));
        (, uint256 assets) = abi.decode(log.data, (address, uint256));
        jSupplyCol = _app(
            jSupplyCol,
            string.concat(
                _sb("id_", _b32s(_id)),
                _c,
                _sb("collateral", _as(token)),
                _c,
                _sb("onbehalf", _as(onB)),
                _c,
                _sn("assets", assets),
                _c,
                _sn("evt_block_number", bn),
                _c,
                _sn("evt_index", idx)
            )
        );
    }

    function _decodeWithdrawCol(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        bytes32 _id = log.topics[1];
        address token = address(uint160(uint256(log.topics[2])));
        address onB = address(uint160(uint256(log.topics[3])));
        (, uint256 assets,) = abi.decode(log.data, (address, uint256, address));
        jWithdrawCol = _app(
            jWithdrawCol,
            string.concat(
                _sb("id_", _b32s(_id)),
                _c,
                _sb("collateral", _as(token)),
                _c,
                _sb("onbehalf", _as(onB)),
                _c,
                _sn("assets", assets),
                _c,
                _sn("evt_block_number", bn),
                _c,
                _sn("evt_index", idx)
            )
        );
    }

    // Reads actual initial fee values from the contract after touchMarket initialises them.
    function _decodeMarketCreated(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        bytes32 _id = log.topics[1];
        Market memory mkt = abi.decode(log.data, (Market));
        string memory body;
        // Split into two scoped blocks to keep live variables under the Yul stack limit.
        {
            uint16 tf0;
            uint16 tf1;
            uint16 tf2;
            uint16 tf3;
            (,,,, tf0, tf1, tf2, tf3,,,,,) = midnight.marketState(_id);
            body = string.concat(
                _sb("id_", _b32s(_id)),
                _c,
                _sb("market_loantoken", _as(mkt.loanToken)),
                _c,
                _sn("market_maturity", mkt.maturity),
                _c,
                _sn("market_settlementfeecbp0", tf0),
                _c,
                _sn("market_settlementfeecbp1", tf1),
                _c,
                _sn("market_settlementfeecbp2", tf2),
                _c,
                _sn("market_settlementfeecbp3", tf3)
            );
        }
        {
            uint16 tf4;
            uint16 tf5;
            uint16 tf6;
            uint32 cf;
            (,,,,,,,, tf4, tf5, tf6, cf,) = midnight.marketState(_id);
            body = string.concat(
                body,
                _c,
                _sn("market_settlementfeecbp4", tf4),
                _c,
                _sn("market_settlementfeecbp5", tf5),
                _c,
                _sn("market_settlementfeecbp6", tf6),
                _c,
                _sn("market_continuousfee", cf),
                _c,
                _sn("evt_block_number", bn),
                _c,
                _sn("evt_index", idx)
            );
        }
        jMarketCreated = _app(jMarketCreated, body);
    }

    function _decodeSetConsumed(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        bytes32 grp = log.topics[2];
        address onB = address(uint160(uint256(log.topics[3])));
        (uint256 amount) = abi.decode(log.data, (uint256));
        jSetConsumed = _app(
            jSetConsumed,
            string.concat(
                _sb("onbehalf", _as(onB)),
                _c,
                _sb("group", _b32s(grp)),
                _c,
                _sn("amount", amount),
                _c,
                _sn("evt_block_number", bn),
                _c,
                _sn("evt_index", idx)
            )
        );
    }

    function _decodeSetIsAuth(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        address auth = address(uint160(uint256(log.topics[2])));
        address onB = address(uint160(uint256(log.topics[3])));
        (bool val) = abi.decode(log.data, (bool));
        jSetIsAuth = _app(
            jSetIsAuth,
            string.concat(
                _sb("onbehalf", _as(onB)),
                _c,
                _sb("authorized", _as(auth)),
                _c,
                _nb("newisauthorized", val ? "true" : "false"),
                _c,
                _sn("evt_block_number", bn),
                _c,
                _sn("evt_index", idx)
            )
        );
    }

    function _decodeSetDefTf(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        address lt = address(uint160(uint256(log.topics[1])));
        uint256 ix = uint256(log.topics[2]);
        (uint256 fee) = abi.decode(log.data, (uint256));
        jSetDefTf = _app(
            jSetDefTf,
            string.concat(
                _sb("loantoken", _as(lt)),
                _c,
                _sn("index", ix),
                _c,
                _sn("newsettlementfee", fee),
                _c,
                _sn("evt_block_number", bn),
                _c,
                _sn("evt_index", idx)
            )
        );
    }

    function _decodeSetMktTf(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        bytes32 _id = log.topics[1];
        uint256 ix = uint256(log.topics[2]);
        (uint256 fee) = abi.decode(log.data, (uint256));
        jSetMktTf = _app(
            jSetMktTf,
            string.concat(
                _sb("id_", _b32s(_id)),
                _c,
                _sn("index", ix),
                _c,
                _sn("newsettlementfee", fee),
                _c,
                _sn("evt_block_number", bn),
                _c,
                _sn("evt_index", idx)
            )
        );
    }

    function _decodeSetMktCf(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        bytes32 _id = log.topics[1];
        (uint256 fee) = abi.decode(log.data, (uint256));
        jSetMktCf = _app(
            jSetMktCf,
            string.concat(
                _sb("id_", _b32s(_id)),
                _c,
                _sn("newcontinuousfee", fee),
                _c,
                _sn("evt_block_number", bn),
                _c,
                _sn("evt_index", idx)
            )
        );
    }

    function _decodeClaimTf(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        address token = address(uint160(uint256(log.topics[2])));
        (uint256 amount) = abi.decode(log.data, (uint256));
        jClaimTf = _app(
            jClaimTf,
            string.concat(
                _sb("token", _as(token)),
                _c,
                _sn("amount", amount),
                _c,
                _sn("evt_block_number", bn),
                _c,
                _sn("evt_index", idx)
            )
        );
    }

    function _decodeClaimCf(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        bytes32 _id = log.topics[2];
        (uint256 amount) = abi.decode(log.data, (uint256));
        jClaimCf = _app(
            jClaimCf,
            string.concat(
                _sb("id_", _b32s(_id)),
                _c,
                _sn("amount", amount),
                _c,
                _sn("evt_block_number", bn),
                _c,
                _sn("evt_index", idx)
            )
        );
    }

    function _decodeConstructor(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        address rs = address(uint160(uint256(log.topics[1])));
        jConstructor = _app(
            jConstructor,
            string.concat(_sb("rolesetter", _as(rs)), _c, _sn("evt_block_number", bn), _c, _sn("evt_index", idx))
        );
    }

    function _decodeSetFeeSetter(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        address a = address(uint160(uint256(log.topics[1])));
        jSetFeeSetter = _app(
            jSetFeeSetter,
            string.concat(_sb("feesetter", _as(a)), _c, _sn("evt_block_number", bn), _c, _sn("evt_index", idx))
        );
    }

    function _decodeSetFeeClaimer(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        address a = address(uint160(uint256(log.topics[1])));
        jSetFeeClaimer = _app(
            jSetFeeClaimer,
            string.concat(_sb("feeclaimer", _as(a)), _c, _sn("evt_block_number", bn), _c, _sn("evt_index", idx))
        );
    }

    function _decodeSetTsSetter(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        address a = address(uint160(uint256(log.topics[1])));
        jSetTsSetter = _app(
            jSetTsSetter,
            string.concat(_sb("tickspacingsetter", _as(a)), _c, _sn("evt_block_number", bn), _c, _sn("evt_index", idx))
        );
    }

    function _decodeSetDefCf(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        address lt = address(uint160(uint256(log.topics[1])));
        (uint256 fee) = abi.decode(log.data, (uint256));
        jSetDefCf = _app(
            jSetDefCf,
            string.concat(
                _sb("loantoken", _as(lt)),
                _c,
                _sn("newcontinuousfee", fee),
                _c,
                _sn("evt_block_number", bn),
                _c,
                _sn("evt_index", idx)
            )
        );
    }

    function _decodeLiquidate(Vm.Log memory log, uint256 bn, uint256 idx) internal {
        bytes32 _id = log.topics[1];
        address collat = address(uint160(uint256(log.topics[2])));
        address borrowerAddr = address(uint160(uint256(log.topics[3])));
        // data: caller, seizedAssets, repaidUnits, postMaturityMode, receiver, payer, badDebt, latestLossFactor,
        // latestContinuousFeeCredit
        (, uint256 seized, uint256 repaid, bool pmMode,,, uint256 bad, uint256 latestLF, uint256 latestCFC) =
            abi.decode(log.data, (address, uint256, uint256, bool, address, address, uint256, uint256, uint256));
        string memory body = string.concat(
            _sb("id_", _b32s(_id)),
            _c,
            _sb("collateral", _as(collat)),
            _c,
            _sb("borrower", _as(borrowerAddr)),
            _c,
            _sn("seizedassets", seized),
            _c,
            _sn("repaidunits", repaid),
            _c,
            _nb("postmaturitymode", pmMode ? "true" : "false"),
            _c,
            _sn("baddebt", bad),
            _c,
            _sn("latestlossfactor", latestLF)
        );
        body = string.concat(
            body,
            _c,
            _sn("latestcontinuousfeecredit", latestCFC),
            _c,
            _sn("evt_block_number", bn),
            _c,
            _sn("evt_index", idx)
        );
        jLiquidate = _app(jLiquidate, body);
    }

    // ── Manually append setUp events (block 1)
    // ────────────────────────────────

    function _appendSetUpEvents() internal {
        // Constructor
        jConstructor = _app(
            jConstructor,
            string.concat(
                _sb("rolesetter", _as(address(this))), _c, _sn("evt_block_number", 1), _c, _sn("evt_index", logIdx++)
            )
        );
        // SetFeeSetter
        jSetFeeSetter = _app(
            jSetFeeSetter,
            string.concat(
                _sb("feesetter", _as(address(this))), _c, _sn("evt_block_number", 1), _c, _sn("evt_index", logIdx++)
            )
        );
        // SetTickSpacingSetter
        jSetTsSetter = _app(
            jSetTsSetter,
            string.concat(
                _sb("tickspacingsetter", _as(address(this))),
                _c,
                _sn("evt_block_number", 1),
                _c,
                _sn("evt_index", logIdx++)
            )
        );
        // SetIsAuthorized ×4 (each user authorises ecrecoverRatifier in setUp)
        address[4] memory users = [borrower, lender, otherBorrower, otherLender];
        for (uint256 i = 0; i < 4; i++) {
            jSetIsAuth = _app(
                jSetIsAuth,
                string.concat(
                    _sb("onbehalf", _as(users[i])),
                    _c,
                    _sb("authorized", _as(address(ecrecoverRatifier))),
                    _c,
                    _nb("newisauthorized", "true"),
                    _c,
                    _sn("evt_block_number", 1),
                    _c,
                    _sn("evt_index", logIdx++)
                )
            );
        }
        // SetFeeClaimer (called in SqlScenarioTest.setUp)
        jSetFeeClaimer = _app(
            jSetFeeClaimer,
            string.concat(
                _sb("feeclaimer", _as(address(this))), _c, _sn("evt_block_number", 1), _c, _sn("evt_index", logIdx++)
            )
        );
    }

    // ── Write output files
    // ────────────────────────────────────────────────────

    function _writeOutput() internal {
        string memory dir = "sql/test/events/";
        vm.writeFile(string.concat(dir, "take.json"), string.concat(jTake, "]"));
        vm.writeFile(string.concat(dir, "updateposition.json"), string.concat(jUpdatePos, "]"));
        vm.writeFile(string.concat(dir, "withdraw.json"), string.concat(jWithdraw, "]"));
        vm.writeFile(string.concat(dir, "repay.json"), string.concat(jRepay, "]"));
        vm.writeFile(string.concat(dir, "supplycollateral.json"), string.concat(jSupplyCol, "]"));
        vm.writeFile(string.concat(dir, "withdrawcollateral.json"), string.concat(jWithdrawCol, "]"));
        vm.writeFile(string.concat(dir, "marketcreated.json"), string.concat(jMarketCreated, "]"));
        vm.writeFile(string.concat(dir, "setconsumed.json"), string.concat(jSetConsumed, "]"));
        vm.writeFile(string.concat(dir, "setisauthorized.json"), string.concat(jSetIsAuth, "]"));
        vm.writeFile(string.concat(dir, "setdefaultsettlementfee.json"), string.concat(jSetDefTf, "]"));
        vm.writeFile(string.concat(dir, "setmarketsettlementfee.json"), string.concat(jSetMktTf, "]"));
        vm.writeFile(string.concat(dir, "setmarketcontinuousfee.json"), string.concat(jSetMktCf, "]"));
        vm.writeFile(string.concat(dir, "claimsettlementfee.json"), string.concat(jClaimTf, "]"));
        vm.writeFile(string.concat(dir, "claimcontinuousfee.json"), string.concat(jClaimCf, "]"));
        vm.writeFile(string.concat(dir, "constructor.json"), string.concat(jConstructor, "]"));
        vm.writeFile(string.concat(dir, "setfeesetter.json"), string.concat(jSetFeeSetter, "]"));
        vm.writeFile(string.concat(dir, "setfeeclaimer.json"), string.concat(jSetFeeClaimer, "]"));
        vm.writeFile(string.concat(dir, "settickspacingsetter.json"), string.concat(jSetTsSetter, "]"));
        vm.writeFile(string.concat(dir, "setdefaultcontinuousfee.json"), string.concat(jSetDefCf, "]"));
        vm.writeFile(string.concat(dir, "liquidate.json"), string.concat(jLiquidate, "]"));

        _writeExpectedState();
    }

    function _writeExpectedState() internal {
        string memory j = "{";
        j = string.concat(j, '"lender_addr":"', _as(lender), '",');
        j = string.concat(j, '"borrower_addr":"', _as(borrower), '",');
        j = string.concat(j, '"other_lender_addr":"', _as(otherLender), '",');
        j = string.concat(j, '"other_borrower_addr":"', _as(otherBorrower), '",');
        j = string.concat(j, '"loan_token_addr":"', _as(address(loanToken)), '",');
        j = string.concat(j, '"market_id":"', _b32s(id), '",');
        j = string.concat(j, '"group_a":"', _b32s(GROUP_A), '",');
        j = string.concat(j, '"position_lender":{', _posJson(id, lender), "},");
        j = string.concat(j, '"position_borrower":{', _posJson(id, borrower), "},");
        j = string.concat(j, '"position_other_borrower":{', _posJson(id, otherBorrower), "},");
        j = string.concat(j, '"borrower_collateral_0":', _us(midnight.collateral(id, borrower, 0)), ",");
        j = string.concat(j, '"market_state":{', _mktStateJson(), "},");
        j = string.concat(j, '"consumed_borrower_group_a":', _us(midnight.consumed(borrower, GROUP_A)), ",");
        bool isAuth = midnight.isAuthorized(lender, otherLender);
        j = string.concat(j, '"is_authorized_lender_other_lender":', isAuth ? "true" : "false", ",");
        j = string.concat(
            j, '"claimable_settlement_fee":', _us(midnight.claimableSettlementFee(address(loanToken))), ","
        );
        j = string.concat(
            j, '"default_settlement_fee_cbp_3":', _us(midnight.defaultSettlementFeeCbp(address(loanToken), 3)), ","
        );
        j = string.concat(j, '"default_continuous_fee":', _us(midnight.defaultContinuousFee(address(loanToken))), ",");
        j = string.concat(j, '"role_setter":"', _as(midnight.roleSetter()), '",');
        j = string.concat(j, '"fee_setter":"', _as(midnight.feeSetter()), '",');
        j = string.concat(j, '"fee_claimer":"', _as(midnight.feeClaimer()), '",');
        j = string.concat(j, '"tick_spacing_setter":"', _as(midnight.tickSpacingSetter()), '"');
        j = string.concat(j, "}");
        vm.writeFile("sql/test/expected_state.json", j);
    }

    // ── Market-state helpers (split to avoid Yul stack depth limits) ──────────

    function _posJson(bytes32 _id, address user) internal view returns (string memory) {
        (uint128 credit, uint128 pendingFee, uint128 lastLF, uint128 lastAccrual, uint128 debt,) =
            midnight.position(_id, user);
        return string.concat(
            _sn("credit", credit),
            _c,
            _sn("pending_fee", pendingFee),
            _c,
            _sn("last_loss_factor", lastLF),
            _c,
            _sn("last_accrual", lastAccrual),
            _c,
            _sn("debt", debt)
        );
    }

    function _mktStateJson() internal view returns (string memory) {
        string memory s = string.concat(_mktStateCoreJson(), _c, _mktStateFeesJson());
        return string.concat(s, _c, _mktStateLastJson());
    }

    function _mktStateCoreJson() internal view returns (string memory) {
        (uint128 totalUnits, uint128 lossFactor, uint128 withdrawable, uint128 cfc,,,,,,,,,) = midnight.marketState(id);
        return string.concat(
            _sn("total_units", totalUnits),
            _c,
            _sn("loss_factor", lossFactor),
            _c,
            _sn("withdrawable", withdrawable),
            _c,
            _sn("continuous_fee_credit", cfc)
        );
    }

    function _mktStateFeesJson() internal view returns (string memory) {
        (,,,, uint16 tf0, uint16 tf1, uint16 tf2, uint16 tf3, uint16 tf4, uint16 tf5, uint16 tf6,,) =
            midnight.marketState(id);
        string memory s = string.concat(
            _sn("settlement_fee_cbp_0", tf0),
            _c,
            _sn("settlement_fee_cbp_1", tf1),
            _c,
            _sn("settlement_fee_cbp_2", tf2),
            _c,
            _sn("settlement_fee_cbp_3", tf3)
        );
        return string.concat(
            s,
            _c,
            _sn("settlement_fee_cbp_4", tf4),
            _c,
            _sn("settlement_fee_cbp_5", tf5),
            _c,
            _sn("settlement_fee_cbp_6", tf6)
        );
    }

    function _mktStateLastJson() internal view returns (string memory) {
        (,,,,,,,,,,, uint32 contFee, uint8 tickSpacing) = midnight.marketState(id);
        return string.concat(_sn("continuous_fee", contFee), _c, _sn("tick_spacing", tickSpacing));
    }

    // ── JSON helpers
    // ──────────────────────────────────────────────────────────

    string internal constant _c = ",";

    // Reads the i-th 32-byte ABI word (0-indexed) from ABI-encoded bytes memory.
    function _word(bytes memory d, uint256 i) private pure returns (bytes32 v) {
        assembly ("memory-safe") { v := mload(add(add(d, 32), mul(i, 32))) }
    }

    function merkleRatifierData(Offer[1] memory offers) internal view returns (bytes memory) {
        bytes32 _root = HashLib.hashOffer(offers[0]);
        bytes32[] memory _proof = new bytes32[](0);
        Signature memory _sig = signature(_root, privateKey[offers[0].maker], offers[0].ratifier, 0);
        return abi.encode(_sig, _root, 0, _proof);
    }

    function _app(string memory arr, string memory obj) internal pure returns (string memory) {
        bool empty = bytes(arr).length == 1;
        return string.concat(arr, empty ? "" : ",", "{", obj, "}");
    }

    function _sb(string memory k, string memory v) internal pure returns (string memory) {
        return string.concat('"', k, '":"', v, '"');
    }

    function _sn(string memory k, uint256 v) internal pure returns (string memory) {
        return string.concat('"', k, '":"', vm.toString(v), '"');
    }

    function _nb(string memory k, string memory v) internal pure returns (string memory) {
        return string.concat('"', k, '":', v);
    }

    function _as(address a) internal pure returns (string memory) {
        return vm.toString(a);
    }

    function _b32s(bytes32 b) internal pure returns (string memory) {
        return vm.toString(b);
    }

    function _us(uint256 v) internal pure returns (string memory) {
        return string.concat('"', vm.toString(v), '"');
    }
}
