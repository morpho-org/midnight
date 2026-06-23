// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {console2} from "../lib/forge-std/src/console2.sol";
import {Market, Offer, CollateralParams} from "../src/interfaces/IMidnight.sol";

/// @dev Harness that isolates the cost of emitting the Take event in its two variants.
///      Both functions read all inputs from storage (constants would be folded at compile time,
///      storage loads are not), return a value derived from the inputs (defeats DCE), and emit
///      exactly one event. The external-call overhead is identical for both variants and cancels
///      in the delta.
contract EventGasHarness {
    // --- full-offer variant (log-more / current branch) ---
    event TakeFull(
        address caller,
        bytes32 indexed id_,
        uint256 units,
        address indexed taker,
        Offer offer,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 consumed,
        uint256 buyerPendingFeeIncrease,
        uint256 sellerPendingFeeDecrease,
        uint256 buyerCreditIncrease,
        uint256 sellerCreditDecrease,
        address receiver,
        address payer,
        address takerCallback
    );

    // --- scalar variant (origin/main) ---
    event TakeScalar(
        address caller,
        bytes32 indexed id_,
        uint256 units,
        address indexed taker,
        address indexed maker,
        bool offerIsBuy,
        bytes32 group,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 consumed,
        uint256 buyerPendingFeeIncrease,
        uint256 sellerPendingFeeDecrease,
        uint256 buyerCreditIncrease,
        uint256 sellerCreditDecrease,
        address receiver,
        address payer
    );

    // storage-backed inputs
    Offer internal offer;
    address internal caller;
    bytes32 internal id_;
    uint256 internal units;
    address internal taker;
    uint256 internal buyerAssets;
    uint256 internal sellerAssets;
    uint256 internal consumed;
    uint256 internal buyerPendingFeeIncrease;
    uint256 internal sellerPendingFeeDecrease;
    uint256 internal buyerCreditIncrease;
    uint256 internal sellerCreditDecrease;
    address internal receiver;
    address internal payer;
    address internal takerCallback;

    function setOffer(Offer memory o) external {
        offer = o;
    }

    function setScalars(
        address _caller,
        bytes32 _id,
        uint256 _units,
        address _taker,
        uint256 _buyerAssets,
        uint256 _sellerAssets,
        uint256 _consumed,
        uint256 _buyerPendingFeeIncrease,
        uint256 _sellerPendingFeeDecrease,
        uint256 _buyerCreditIncrease,
        uint256 _sellerCreditDecrease,
        address _receiver,
        address _payer,
        address _takerCallback
    ) external {
        caller = _caller;
        id_ = _id;
        units = _units;
        taker = _taker;
        buyerAssets = _buyerAssets;
        sellerAssets = _sellerAssets;
        consumed = _consumed;
        buyerPendingFeeIncrease = _buyerPendingFeeIncrease;
        sellerPendingFeeDecrease = _sellerPendingFeeDecrease;
        buyerCreditIncrease = _buyerCreditIncrease;
        sellerCreditDecrease = _sellerCreditDecrease;
        receiver = _receiver;
        payer = _payer;
        takerCallback = _takerCallback;
    }

    function logFull() external returns (uint256) {
        Offer memory o = offer;
        emit TakeFull(
            caller,
            id_,
            units,
            taker,
            o,
            buyerAssets,
            sellerAssets,
            consumed,
            buyerPendingFeeIncrease,
            sellerPendingFeeDecrease,
            buyerCreditIncrease,
            sellerCreditDecrease,
            receiver,
            payer,
            takerCallback
        );
        // derive a return value from inputs so the call cannot be DCE'd
        return units ^ uint256(uint160(caller)) ^ o.market.maturity ^ o.callbackData.length;
    }

    function logScalar() external returns (uint256) {
        Offer memory o = offer;
        emit TakeScalar(
            caller,
            id_,
            units,
            taker,
            o.maker,
            o.buy,
            o.group,
            buyerAssets,
            sellerAssets,
            consumed,
            buyerPendingFeeIncrease,
            sellerPendingFeeDecrease,
            buyerCreditIncrease,
            sellerCreditDecrease,
            receiver,
            payer
        );
        return units ^ uint256(uint160(caller)) ^ uint256(uint160(o.maker)) ^ uint256(o.group);
    }
}

contract EventGasCompare is Test {
    EventGasHarness internal harness;
    uint256 internal sink;

    function setUp() public {
        harness = new EventGasHarness();

        harness.setScalars(
            address(0xCA11),
            bytes32(uint256(0x1D)),
            1e18,
            address(0x7A1E),
            123e18,
            456e18,
            789e18,
            111e18,
            222e18,
            333e18,
            444e18,
            address(0x4ECE),
            address(0xBABE),
            address(0xCB)
        );
    }

    /// @dev Builds an Offer with `numCollateral` collateral params and `callbackLen` bytes of
    ///      callbackData. All scalar fields are non-zero.
    function _buildOffer(uint256 numCollateral, uint256 callbackLen) internal pure returns (Offer memory o) {
        o.market.loanToken = address(0x10A4);
        o.market.maturity = 100 days;
        o.market.rcfThreshold = 7;
        o.market.enterGate = address(0xE47E);
        o.market.liquidatorGate = address(0x11D4);
        o.market.collateralParams = new CollateralParams[](numCollateral);
        for (uint256 i; i < numCollateral; ++i) {
            o.market.collateralParams[i] = CollateralParams({
                token: address(uint160(0xC011 + i)),
                lltv: 0.77e18 + i,
                maxLif: 1.1e18 + i,
                oracle: address(uint160(0x04AC + i))
            });
        }

        o.buy = true;
        o.maker = address(0x344E);
        o.start = 1;
        o.expiry = 200 days;
        o.tick = 12345;
        o.group = bytes32(uint256(0x6409));
        o.callback = address(0xCBAC);
        o.callbackData = new bytes(callbackLen);
        for (uint256 i; i < callbackLen; ++i) {
            o.callbackData[i] = bytes1(uint8(0xAB));
        }
        o.receiverIfMakerIsSeller = address(0x4ECE);
        o.ratifier = address(0x4A71);
        o.reduceOnly = false;
        o.maxUnits = type(uint128).max;
        o.maxAssets = type(uint128).max;
        o.continuousFeeCap = 999;
    }

    function _measure(uint256 numCollateral, uint256 callbackLen)
        internal
        returns (uint256 fullGas, uint256 scalarGas)
    {
        harness.setOffer(_buildOffer(numCollateral, callbackLen));

        // warm the storage slots / code with a throwaway call to each, so the measured call
        // reflects steady-state cost (cold->warm SLOAD differences would otherwise bias one path).
        sink += harness.logFull();
        sink += harness.logScalar();

        uint256 g = gasleft();
        uint256 r1 = harness.logFull();
        fullGas = g - gasleft();

        g = gasleft();
        uint256 r2 = harness.logScalar();
        scalarGas = g - gasleft();

        sink += r1 + r2;
    }

    function testEventGasCompare() public {
        uint256[3] memory collats = [uint256(0), 1, 3];
        uint256[3] memory cbLens = [uint256(0), 64, 256];

        console2.log("collats | cbLen | fullGas | scalarGas | delta");
        for (uint256 i; i < collats.length; ++i) {
            for (uint256 j; j < cbLens.length; ++j) {
                (uint256 fullGas, uint256 scalarGas) = _measure(collats[i], cbLens[j]);
                uint256 delta = fullGas - scalarGas;
                console2.log(collats[i], cbLens[j], fullGas, scalarGas);
                console2.log("  delta:", delta);
            }
        }

        // keep sink alive
        emit log_named_uint("sink", sink);
    }
}
