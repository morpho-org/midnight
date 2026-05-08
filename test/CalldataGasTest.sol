// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {console2} from "../lib/forge-std/src/console2.sol";
import {BaseTest, MAX_TEST_AMOUNT} from "./BaseTest.sol";
import {Obligation, CollateralParams, Offer, IMidnight} from "../src/interfaces/IMidnight.sol";
import {
    ORACLE_PRICE_SCALE,
    LIQUIDATION_CURSOR_LOW,
    LLTV_2,
    MAX_COLLATERALS,
    MAX_CONTINUOUS_FEE
} from "../src/libraries/ConstantsLib.sol";
import {Midnight} from "../src/Midnight.sol";
import {ERC20} from "./erc20s/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {MAX_TICK} from "../src/libraries/TickLib.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

contract CalldataGasTest is BaseTest {
    Obligation internal obligation;
    bytes32 internal storedId;
    uint256 internal storedUnits;

    function setUp() public override {
        super.setUp();

        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 1000;
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken1),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, LIQUIDATION_CURSOR_LOW),
                    oracle: address(oracle1)
                })
            );
        obligation.collateralParams
            .push(
                CollateralParams({
                    token: address(collateralToken2),
                    lltv: 0.77e18,
                    maxLif: maxLif(0.77e18, LIQUIDATION_CURSOR_LOW),
                    oracle: address(oracle2)
                })
            );
        obligation.collateralParams = sortCollateralParams(obligation.collateralParams);
        obligation.rcfThreshold = 0;

        vm.prank(borrower);
        midnight.setIsAuthorized(borrower, address(this), true);
        vm.prank(lender);
        midnight.setIsAuthorized(lender, address(this), true);

        storedUnits = 1_000_000;
        collateralize(obligation, borrower, storedUnits);
        setupObligation(obligation, storedUnits);
        storedId = toId(obligation);
    }

    function test_gas_touchObligation() public {
        Obligation memory _o = obligation;
        uint256 g = gasleft();
        bytes32 id = midnight.touchObligation(_o);
        g = g - gasleft();
        require(id == storedId, "touchObligation");
        console2.log("touchObligation", g);
    }

    function test_gas_toId() public view {
        Obligation memory _o = obligation;
        uint256 g = gasleft();
        bytes32 id = midnight.toId(_o);
        g = g - gasleft();
        require(id == storedId, "toId");
        console2.log("toId", g);
    }

    function test_gas_updatePosition() public {
        Obligation memory _o = obligation;
        uint256 g = gasleft();
        (uint128 c,,) = midnight.updatePosition(_o, borrower);
        g = g - gasleft();
        require(c >= 0, "updatePosition");
        console2.log("updatePosition", g);
    }

    function test_gas_repay() public {
        Obligation memory _o = obligation;
        uint256 amount = storedUnits / 2;
        deal(address(loanToken), borrower, amount);
        vm.prank(borrower);
        loanToken.approve(address(midnight), amount);

        vm.prank(borrower);
        uint256 g = gasleft();
        midnight.repay(_o, amount, borrower, address(0), hex"");
        g = g - gasleft();
        console2.log("repay", g);
    }

    function test_gas_withdraw() public {
        Obligation memory _o = obligation;
        uint256 amount = storedUnits / 2;
        deal(address(loanToken), borrower, amount);
        vm.prank(borrower);
        loanToken.approve(address(midnight), amount);
        vm.prank(borrower);
        midnight.repay(_o, amount, borrower, address(0), hex"");

        vm.prank(lender);
        uint256 g = gasleft();
        midnight.withdraw(_o, amount, lender, lender);
        g = g - gasleft();
        console2.log("withdraw", g);
    }

    function test_gas_supplyCollateral() public {
        Obligation memory _o = obligation;
        uint256 amount = 1_000;
        deal(_o.collateralParams[0].token, address(this), amount);

        uint256 g = gasleft();
        midnight.supplyCollateral(_o, 0, amount, borrower);
        g = g - gasleft();
        console2.log("supplyCollateral", g);
    }

    function test_gas_withdrawCollateral() public {
        Obligation memory _o = obligation;
        uint256 amount = 1_000;
        deal(_o.collateralParams[0].token, address(this), amount);
        midnight.supplyCollateral(_o, 0, amount, address(this));

        uint256 g = gasleft();
        midnight.withdrawCollateral(_o, 0, amount, address(this), address(this));
        g = g - gasleft();
        console2.log("withdrawCollateral", g);
    }

    function _runLiquidate(uint256 nCollaterals) internal returns (uint256) {
        Oracle[] memory oracles = new Oracle[](nCollaterals);
        Obligation memory o;
        o.loanToken = address(loanToken);
        o.maturity = block.timestamp + 1000;
        CollateralParams[] memory cps = new CollateralParams[](nCollaterals);
        for (uint256 i; i < nCollaterals; ++i) {
            ERC20 t = new ERC20("c", "c");
            oracles[i] = new Oracle();
            cps[i] = CollateralParams({
                token: address(t),
                lltv: LLTV_2,
                maxLif: maxLif(LLTV_2, LIQUIDATION_CURSOR_LOW),
                oracle: address(oracles[i])
            });
        }
        cps = sortCollateralParams(cps);
        o.collateralParams = cps;

        uint256 units = 100_000;
        uint256 collatPerLeg = 1_000_000;
        for (uint256 i; i < nCollaterals; ++i) {
            address t = o.collateralParams[i].token;
            deal(t, otherBorrower, collatPerLeg);
            vm.prank(otherBorrower);
            ERC20(t).approve(address(midnight), type(uint256).max);
            vm.prank(otherBorrower);
            midnight.supplyCollateral(o, i, collatPerLeg, otherBorrower);
        }

        deal(address(loanToken), otherLender, units);
        Offer memory offer;
        offer.obligation = o;
        offer.buy = false;
        offer.maker = otherBorrower;
        offer.receiverIfMakerIsSeller = otherBorrower;
        offer.maxUnits = units;
        offer.ratifier = address(ecrecoverRatifier);
        offer.start = block.timestamp;
        offer.expiry = block.timestamp;
        offer.tick = MAX_TICK;
        bytes memory _ratifierData = ratifierData([offer]);
        bytes32 _root = root([offer]);
        bytes32[] memory _proof = proof([offer]);
        vm.prank(otherLender);
        midnight.take(units, otherLender, address(0), hex"", otherBorrower, offer, _ratifierData, _root, _proof);

        for (uint256 i; i < nCollaterals; ++i) {
            oracles[i].setPrice(ORACLE_PRICE_SCALE / 100);
        }

        Obligation memory _o = o;
        uint256 g = gasleft();
        (uint256 sa, uint256 ru) = midnight.liquidate(_o, 0, 0, 0, otherBorrower, address(this), address(0), "");
        g = g - gasleft();
        require(sa == sa && ru == ru, "use returns");
        return g;
    }

    function test_gas_liquidate_4_collaterals() public {
        uint256 g = _runLiquidate(4);
        console2.log("liquidate (4 collaterals)", g);
    }

    function test_gas_liquidate_1_collateral() public {
        uint256 g = _runLiquidate(1);
        console2.log("liquidate (1 collateral)", g);
    }

    /// @dev Builds a fresh obligation with `n` collaterals using synthetic addresses.
    /// touchObligation/toId/toObligation/sstore2/obligationState do not call into token/oracle code,
    /// so synthetic addresses suffice.
    function _buildObligation(uint256 n) internal view returns (Obligation memory o) {
        o.loanToken = address(loanToken);
        o.maturity = block.timestamp + 1000;
        o.rcfThreshold = 0;
        CollateralParams[] memory cps = new CollateralParams[](n);
        for (uint256 i = 0; i < n; i++) {
            cps[i] = CollateralParams({
                token: address(uint160(0x1000 + i)),
                lltv: 0.77e18,
                maxLif: maxLif(0.77e18, LIQUIDATION_CURSOR_LOW),
                oracle: address(uint160(0x9000 + i))
            });
        }
        o.collateralParams = cps;
    }

    function test_gas_touchObligation_create_5coll() public {
        Obligation memory _o = _buildObligation(5);
        uint256 g = gasleft();
        bytes32 id = midnight.touchObligation(_o);
        g = g - gasleft();
        require(id != bytes32(0), "touchObligation_create");
        console2.log("touchObligation_create_5coll", g);
    }

    function test_gas_touchObligation_create_50coll() public {
        Obligation memory _o = _buildObligation(50);
        uint256 g = gasleft();
        bytes32 id = midnight.touchObligation(_o);
        g = g - gasleft();
        require(id != bytes32(0), "touchObligation_create");
        console2.log("touchObligation_create_50coll", g);
    }

    function test_gas_toId_fresh_5coll() public view {
        Obligation memory _o = _buildObligation(5);
        uint256 g = gasleft();
        bytes32 id = midnight.toId(_o);
        g = g - gasleft();
        require(id != bytes32(0), "toId_fresh");
        console2.log("toId_fresh_5coll", g);
    }

    function test_gas_toId_fresh_50coll() public view {
        Obligation memory _o = _buildObligation(50);
        uint256 g = gasleft();
        bytes32 id = midnight.toId(_o);
        g = g - gasleft();
        require(id != bytes32(0), "toId_fresh");
        console2.log("toId_fresh_50coll", g);
    }

    function test_gas_toObligation_5coll() public {
        Obligation memory _o = _buildObligation(5);
        bytes32 id = midnight.touchObligation(_o);
        uint256 g = gasleft();
        Obligation memory roundTrip = midnight.toObligation(id);
        g = g - gasleft();
        require(roundTrip.loanToken == _o.loanToken, "toObligation");
        console2.log("toObligation_5coll", g);
    }

    function test_gas_toObligation_50coll() public {
        Obligation memory _o = _buildObligation(50);
        bytes32 id = midnight.touchObligation(_o);
        uint256 g = gasleft();
        Obligation memory roundTrip = midnight.toObligation(id);
        g = g - gasleft();
        require(roundTrip.loanToken == _o.loanToken, "toObligation");
        console2.log("toObligation_50coll", g);
    }

    function test_gas_sstore2CodeStartsWithStop_5coll() public {
        Obligation memory _o = _buildObligation(5);
        bytes32 id = midnight.touchObligation(_o);
        address sstore2Address = address(uint160(uint256(id)));
        uint256 g = gasleft();
        bytes memory code = sstore2Address.code;
        g = g - gasleft();
        require(code.length > 0 && uint8(code[0]) == 0x00, "sstore2");
        console2.log("sstore2CodeStartsWithStop_5coll", g);
    }

    function test_gas_obligationStateGetter_5coll() public {
        Obligation memory _o = _buildObligation(5);
        midnight.setDefaultContinuousFee(_o.loanToken, MAX_CONTINUOUS_FEE);
        for (uint256 i = 0; i < 7; i++) {
            midnight.setDefaultTradingFee(_o.loanToken, i, midnight.maxTradingFee(i));
        }
        bytes32 id = midnight.touchObligation(_o);
        uint256 g = gasleft();
        (,,,,,,,,,,, uint32 _continuousFee, bool created) = midnight.obligationState(id);
        g = g - gasleft();
        require(created && _continuousFee == MAX_CONTINUOUS_FEE, "obligationState");
        console2.log("obligationStateGetter_5coll", g);
    }

    function test_gas_toIdStableAcrossHardfork_5coll() public {
        Obligation memory _o = _buildObligation(5);
        bytes32 idBefore = midnight.touchObligation(_o);
        vm.chainId(uint64(block.chainid + 1));
        uint256 g = gasleft();
        bytes32 idAfter = midnight.toId(_o);
        g = g - gasleft();
        require(idAfter == idBefore, "toIdStableAcrossHardfork");
        console2.log("toIdStableAcrossHardfork_5coll", g);
    }

    function test_gas_belowExactMaxCollaterals() public {
        Obligation memory _o = _buildObligation(MAX_COLLATERALS - 1);
        uint256 g = gasleft();
        bytes32 id = midnight.touchObligation(_o);
        g = g - gasleft();
        require(id != bytes32(0), "belowExactMaxCollaterals");
        console2.log("belowExactMaxCollaterals", g);
    }

    function test_gas_maxCollateralsRevert() public {
        Obligation memory _o = _buildObligation(MAX_COLLATERALS + 1);
        uint256 g = gasleft();
        try midnight.touchObligation(_o) {
            revert("expected revert");
        } catch (bytes memory err) {
            require(bytes4(err) == IMidnight.TooManyCollateralParams.selector, "wrong revert");
        }
        g = g - gasleft();
        console2.log("maxCollateralsRevert", g);
    }

    /// @dev Builds an obligation with `n` real collaterals (deploys ERC20+Oracle each), touches it,
    /// and collateralizes `who` for `units` of debt via collateralParams[0]. Returns the obligation.
    function _setupRealObligation(uint256 n, address who, uint256 units) internal returns (Obligation memory o) {
        o.loanToken = address(loanToken);
        o.maturity = block.timestamp + 1000;
        o.rcfThreshold = 0;
        CollateralParams[] memory cps = new CollateralParams[](n);
        for (uint256 i; i < n; ++i) {
            ERC20 t = new ERC20("c", "c");
            Oracle ora = new Oracle();
            cps[i] = CollateralParams({
                token: address(t), lltv: 0.77e18, maxLif: maxLif(0.77e18, LIQUIDATION_CURSOR_LOW), oracle: address(ora)
            });
        }
        cps = sortCollateralParams(cps);
        o.collateralParams = cps;

        midnight.touchObligation(o);
        collateralize(o, who, units);
    }

    function _runTakeSell(uint256 nColl, string memory label) internal {
        uint256 units = 100_000;
        Obligation memory _o = _setupRealObligation(nColl, otherBorrower, units);
        deal(address(loanToken), otherLender, units);

        Offer memory offer;
        offer.obligation = _o;
        offer.buy = false;
        offer.maker = otherBorrower;
        offer.receiverIfMakerIsSeller = otherBorrower;
        offer.maxUnits = units;
        offer.ratifier = address(ecrecoverRatifier);
        offer.start = block.timestamp;
        offer.expiry = block.timestamp;
        offer.tick = MAX_TICK;
        offer.group = keccak256(abi.encodePacked("take_sell_", label));

        bytes32 _root = root([offer]);
        bytes memory _ratifierData = ratifierData([offer]);
        bytes32[] memory _proof = proof([offer]);

        vm.prank(otherLender);
        uint256 g = gasleft();
        (uint256 ba, uint256 sa, uint256 u) =
            midnight.take(units, otherLender, address(0), hex"", otherLender, offer, _ratifierData, _root, _proof);
        g = g - gasleft();
        require(u == units && ba > 0 && sa > 0, "take_sell");
        console2.log(string.concat("take_sell_", label), g);
    }

    function _runTakeBuy(uint256 nColl, string memory label) internal {
        uint256 units = 100_000;
        Obligation memory _o = _setupRealObligation(nColl, otherBorrower, units);
        deal(address(loanToken), otherLender, units);

        Offer memory offer;
        offer.obligation = _o;
        offer.buy = true;
        offer.maker = otherLender;
        offer.maxUnits = units;
        offer.ratifier = address(ecrecoverRatifier);
        offer.start = block.timestamp;
        offer.expiry = block.timestamp;
        offer.tick = MAX_TICK;
        offer.group = keccak256(abi.encodePacked("take_buy_", label));

        bytes32 _root = root([offer]);
        bytes memory _ratifierData = ratifierData([offer]);
        bytes32[] memory _proof = proof([offer]);

        vm.prank(otherBorrower);
        uint256 g = gasleft();
        (uint256 ba, uint256 sa, uint256 u) =
            midnight.take(units, otherBorrower, address(0), hex"", otherBorrower, offer, _ratifierData, _root, _proof);
        g = g - gasleft();
        require(u == units && ba > 0 && sa > 0, "take_buy");
        console2.log(string.concat("take_buy_", label), g);
    }

    function test_gas_take_sell_3coll() public {
        _runTakeSell(3, "3coll");
    }

    function test_gas_take_buy_3coll() public {
        _runTakeBuy(3, "3coll");
    }

    function test_gas_take_sell_4coll() public {
        _runTakeSell(4, "4coll");
    }

    function test_gas_take_buy_4coll() public {
        _runTakeBuy(4, "4coll");
    }

    function test_gas_take_sell_5coll() public {
        _runTakeSell(5, "5coll");
    }

    function test_gas_take_buy_5coll() public {
        _runTakeBuy(5, "5coll");
    }

    /// @dev Take a sell offer with a proof of length `depth`. Tree leaves other than the
    /// real offer are arbitrary (we just hash up the proof to derive a root the ratifier signs).
    function _runTakeSellWithProof(uint256 depth) internal {
        uint256 units = 100_000;
        Obligation memory _o = _setupRealObligation(2, otherBorrower, units);
        deal(address(loanToken), otherLender, units);

        Offer memory offer;
        offer.obligation = _o;
        offer.buy = false;
        offer.maker = otherBorrower;
        offer.receiverIfMakerIsSeller = otherBorrower;
        offer.maxUnits = units;
        offer.ratifier = address(ecrecoverRatifier);
        offer.start = block.timestamp;
        offer.expiry = block.timestamp;
        offer.tick = MAX_TICK;
        offer.group = keccak256(abi.encodePacked("take_proof", depth));

        bytes32[] memory _proof = new bytes32[](depth);
        bytes32 currentHash = utilsLibBridge.hashOffer(offer);
        for (uint256 i = 0; i < depth; i++) {
            _proof[i] = keccak256(abi.encode("sib", i, depth));
            currentHash = UtilsLib.commutativeHash(currentHash, _proof[i]);
        }
        bytes32 _root = currentHash;

        bytes memory _ratifierData =
            abi.encode(signature(_root, privateKey[otherBorrower], address(ecrecoverRatifier), depth), depth);

        vm.prank(otherLender);
        uint256 g = gasleft();
        (uint256 ba, uint256 sa, uint256 u) =
            midnight.take(units, otherLender, address(0), hex"", otherLender, offer, _ratifierData, _root, _proof);
        g = g - gasleft();
        require(u == units && ba > 0 && sa > 0, "take_proof");
        console2.log("take_proof depth", depth, g);
    }

    function test_gas_take_proof_1() public {
        _runTakeSellWithProof(1);
    }

    function test_gas_take_proof_2() public {
        _runTakeSellWithProof(2);
    }

    function test_gas_take_proof_3() public {
        _runTakeSellWithProof(3);
    }

    function test_gas_take_proof_4() public {
        _runTakeSellWithProof(4);
    }

    function test_gas_take_proof_5() public {
        _runTakeSellWithProof(5);
    }

    /// @dev Build a fresh 5-collateral obligation, touch it, return.
    function _setup5collFresh() internal returns (Obligation memory o) {
        o.loanToken = address(loanToken);
        o.maturity = block.timestamp + 1000;
        o.rcfThreshold = 0;
        CollateralParams[] memory cps = new CollateralParams[](5);
        for (uint256 i; i < 5; ++i) {
            ERC20 t = new ERC20("c", "c");
            Oracle ora = new Oracle();
            cps[i] = CollateralParams({
                token: address(t), lltv: 0.77e18, maxLif: maxLif(0.77e18, LIQUIDATION_CURSOR_LOW), oracle: address(ora)
            });
        }
        cps = sortCollateralParams(cps);
        o.collateralParams = cps;
        midnight.touchObligation(o);
    }

    /// @dev Set up otherBorrower with `units` debt and otherLender with `units` credit
    /// against the 5-collateral obligation. Returns the obligation.
    function _setup5collWithPosition(uint256 units) internal returns (Obligation memory _o) {
        _o = _setupRealObligation(5, otherBorrower, units);

        deal(address(loanToken), otherLender, units);
        Offer memory offer;
        offer.obligation = _o;
        offer.buy = false;
        offer.maker = otherBorrower;
        offer.receiverIfMakerIsSeller = otherBorrower;
        offer.maxUnits = units;
        offer.ratifier = address(ecrecoverRatifier);
        offer.start = block.timestamp;
        offer.expiry = block.timestamp;
        offer.tick = MAX_TICK;
        offer.group = keccak256("5coll_setup");

        bytes32 _root = root([offer]);
        bytes memory _ratifierData = ratifierData([offer]);
        bytes32[] memory _proof = proof([offer]);

        vm.prank(otherLender);
        midnight.take(units, otherLender, address(0), hex"", otherLender, offer, _ratifierData, _root, _proof);
    }

    function test_gas_repay_5coll() public {
        uint256 units = 1_000_000;
        Obligation memory _o = _setup5collWithPosition(units);
        uint256 amount = units / 2;
        deal(address(loanToken), otherBorrower, amount);
        vm.prank(otherBorrower);
        loanToken.approve(address(midnight), amount);

        vm.prank(otherBorrower);
        uint256 g = gasleft();
        midnight.repay(_o, amount, otherBorrower, address(0), hex"");
        g = g - gasleft();
        console2.log("repay_5coll", g);
    }

    function test_gas_withdraw_5coll() public {
        uint256 units = 1_000_000;
        Obligation memory _o = _setup5collWithPosition(units);
        uint256 amount = units / 2;
        deal(address(loanToken), otherBorrower, amount);
        vm.prank(otherBorrower);
        loanToken.approve(address(midnight), amount);
        vm.prank(otherBorrower);
        midnight.repay(_o, amount, otherBorrower, address(0), hex"");

        vm.prank(otherLender);
        uint256 g = gasleft();
        midnight.withdraw(_o, amount, otherLender, otherLender);
        g = g - gasleft();
        console2.log("withdraw_5coll", g);
    }

    function test_gas_supplyCollateral_5coll() public {
        Obligation memory _o = _setup5collFresh();
        uint256 amount = 1_000;
        address t = _o.collateralParams[0].token;
        deal(t, address(this), amount);
        ERC20(t).approve(address(midnight), amount);

        uint256 g = gasleft();
        midnight.supplyCollateral(_o, 0, amount, address(this));
        g = g - gasleft();
        console2.log("supplyCollateral_5coll", g);
    }

    function test_gas_withdrawCollateral_5coll() public {
        Obligation memory _o = _setup5collFresh();
        uint256 amount = 1_000;
        address t = _o.collateralParams[0].token;
        deal(t, address(this), amount);
        ERC20(t).approve(address(midnight), amount);
        midnight.supplyCollateral(_o, 0, amount, address(this));

        uint256 g = gasleft();
        midnight.withdrawCollateral(_o, 0, amount, address(this), address(this));
        g = g - gasleft();
        console2.log("withdrawCollateral_5coll", g);
    }

    function test_gas_updatePosition_5coll() public {
        uint256 units = 1_000_000;
        Obligation memory _o = _setup5collWithPosition(units);

        uint256 g = gasleft();
        (uint128 c,,) = midnight.updatePosition(_o, otherLender);
        g = g - gasleft();
        require(c >= 0, "updatePosition_5coll");
        console2.log("updatePosition_5coll", g);
    }

    function test_gas_liquidate_5coll() public {
        uint256 g = _runLiquidate(5);
        console2.log("liquidate_5coll", g);
    }
}
