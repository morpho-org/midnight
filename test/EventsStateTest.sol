// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {stdStorage, StdStorage} from "../lib/forge-std/src/StdStorage.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {BaseTest} from "./BaseTest.sol";
import {Offer, Obligation, Collateral, Seizure} from "../src/interfaces/IMorphoV2.sol";
import {ERC20} from "./helpers/ERC20.sol";
import {Oracle} from "./helpers/Oracle.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";
import {MorphoV2} from "../src/MorphoV2.sol";
import "forge-std/console.sol";

struct TakeEventData {
    uint256 buyerAssets;
    uint256 sellerAssets;
    uint256 obligationUnits;
    uint256 obligationShares;
    Offer offer;
    uint256 obligationTotalUnits;
    uint256 obligationTotalShares;
    uint256 buyerShares;
    uint256 buyerDebt;
    uint256 sellerShares;
    uint256 sellerDebt;
}

contract EventsStateTest is BaseTest {
    using stdStorage for StdStorage;
    using MathLib for uint256;

    StdStorage private store;

    Obligation internal obligation;
    bytes32 internal id;
    Offer internal offer;

    function setUp() public override {
        super.setUp();

        obligation.chainId = block.chainid;
        obligation.loanToken = address(loanToken);
        obligation.maturity = block.timestamp + 365 days;
        obligation.collaterals
            .push(Collateral({token: address(collateralToken1), lltv: 0.75e18, oracle: address(oracle1)}));
        obligation.collaterals
            .push(Collateral({token: address(collateralToken2), lltv: 0.75e18, oracle: address(oracle2)}));
        obligation.collaterals = sortCollaterals(obligation.collaterals);

        id = toId(obligation);

        offer.obligation = obligation;
        offer.start = block.timestamp;
        offer.expiry = block.timestamp + 1 days;
        offer.startPrice = 1e18;
        offer.expiryPrice = 1e18;
    }

    /// forge-config: default.fuzz.runs = 1024
    function testTakeEvent(uint256 seed) public {
        vm.setSeed(seed);
        setupState();

        offer.buy = vm.randomBool();

        uint256 amountType = vm.randomUint(0, 2);
        if (amountType == 0) offer.assets = vm.randomUint(2e18, 10e18);
        else if (amountType == 1) offer.obligationUnits = vm.randomUint(2e18, 10e18);
        else offer.obligationShares = vm.randomUint(2e18, 10e18);

        address buyer = vm.randomBool() ? lender : borrower;
        address seller = vm.randomBool() ? otherLender : otherBorrower;
        offer.maker = offer.buy ? buyer : seller;

        uint256 obligationShares = vm.randomUint(0, 1e18);

        uint256 consumedBefore = vm.randomUint(0, 1e18);
        writeConsumed(offer.maker, offer.group, consumedBefore);

        vm.recordLogs();
        take(0, 0, 0, obligationShares, offer.buy ? seller : buyer, offer);
        (, bytes memory data) = findFirstEvent(address(morphoV2), EventsLib.Take.selector);
        (TakeEventData memory eventData) = abi.decode(bytes.concat(abi.encode(0x20), data), (TakeEventData));

        assertEq(eventData.obligationTotalShares, morphoV2.totalShares(id), "total shares");
        assertEq(eventData.obligationTotalUnits, morphoV2.totalUnits(id), "total units");
        assertEq(eventData.buyerShares, morphoV2.sharesOf(buyer, id), "buyer shares");
        assertEq(eventData.sellerShares, morphoV2.sharesOf(seller, id), "seller shares");
        assertEq(morphoV2.debtOf(buyer, id), eventData.buyerDebt, "buyer debt");
        assertEq(morphoV2.debtOf(seller, id), eventData.sellerDebt, "seller debt");
        assertEq(eventData.obligationShares, obligationShares, "obligation shares");

        uint256 expectedConsumed;

        if (offer.assets > 0) {
            expectedConsumed = offer.buy ? eventData.buyerAssets : eventData.sellerAssets;
        } else if (offer.obligationUnits > 0) {
            expectedConsumed = eventData.obligationUnits;
        } else {
            expectedConsumed = eventData.obligationShares;
        }

        assertEq(morphoV2.consumed(offer.maker, offer.group), consumedBefore + expectedConsumed, "consumed");
    }

    function testWithdrawEvent(uint256 seed) public {
        vm.setSeed(seed);
        setupState();

        uint256 sharesOfBefore = morphoV2.sharesOf(lender, id);
        uint256 totalUnitsBefore = morphoV2.totalUnits(id);
        uint256 totalSharesBefore = morphoV2.totalShares(id);
        uint256 withdrawableBefore = morphoV2.withdrawable(id);

        vm.recordLogs();
        bool withdrawShares = vm.randomBool();
        if (withdrawShares) {
            uint256 withdrawnShares = vm.randomUint(0, sharesOfBefore);
            morphoV2.withdraw(obligation, 0, withdrawnShares, lender);
        } else {
            uint256 unitsOf = sharesOfBefore.mulDivDown(morphoV2.totalUnits(id) + 1, morphoV2.totalShares(id) + 1);
            uint256 withdrawnUnits = vm.randomUint(0, unitsOf);
            morphoV2.withdraw(obligation, withdrawnUnits, 0, lender);
        }

        (, bytes memory data) = findFirstEvent(address(morphoV2), EventsLib.Withdraw.selector);
        (uint256 eventObligationUnits, uint256 eventShares) = abi.decode(data, (uint256, uint256));

        assertEq(morphoV2.sharesOf(lender, id), sharesOfBefore - eventShares, "shares");
        assertEq(morphoV2.withdrawable(id), withdrawableBefore - eventObligationUnits, "withdrawable");
        assertEq(morphoV2.totalUnits(id), totalUnitsBefore - eventObligationUnits, "total units");
        assertEq(morphoV2.totalShares(id), totalSharesBefore - eventShares, "total shares");
    }

    function testRepayEvent(uint256 seed) public {
        vm.setSeed(seed);
        setupState();

        uint256 debtOfBefore = morphoV2.debtOf(borrower, id);
        uint256 withdrawableBefore = morphoV2.withdrawable(id);

        uint256 repaid = vm.randomUint(0, debtOfBefore);

        vm.recordLogs();
        vm.prank(borrower);
        morphoV2.repay(obligation, repaid, borrower);
        (, bytes memory data) = findFirstEvent(address(morphoV2), EventsLib.Repay.selector);
        (uint256 eventObligationUnits) = abi.decode(data, (uint256));

        assertEq(eventObligationUnits, repaid, "obligation units");
        assertEq(morphoV2.debtOf(borrower, id), debtOfBefore - eventObligationUnits, "debt");
        assertEq(morphoV2.withdrawable(id), withdrawableBefore + eventObligationUnits, "withdrawable");
    }

    function testConstructorEvent(address newOwner) public {
        vm.recordLogs();
        vm.prank(newOwner);
        console.log("newOwner", newOwner);
        MorphoV2 newMorphoV2 = new MorphoV2();
        (bytes32[] memory topics,) = findFirstEvent(address(newMorphoV2), EventsLib.Constructor.selector);
        address eventOwner = address(uint160(uint256(topics[1])));
        assertEq(newMorphoV2.owner(), eventOwner, "owner");
    }

    function testSetOwnerEvent(address newOwner) public {
        vm.recordLogs();
        morphoV2.setOwner(newOwner);
        (bytes32[] memory topics,) = findFirstEvent(address(morphoV2), EventsLib.SetOwner.selector);
        address eventOwner = address(uint160(uint256(topics[1])));

        assertEq(morphoV2.owner(), eventOwner, "owner state");
    }

    function testSetFeeSetterEvent(address newFeeSetter) public {
        vm.recordLogs();
        morphoV2.setFeeSetter(newFeeSetter);
        (bytes32[] memory topics,) = findFirstEvent(address(morphoV2), EventsLib.SetFeeSetter.selector);
        address eventFeeSetter = address(uint160(uint256(topics[1])));

        assertEq(morphoV2.feeSetter(), eventFeeSetter, "setter state");
    }

    function testSetTradingFeeEvent(uint256 seed) public {
        vm.setSeed(seed);

        uint256 tradingFee = vm.randomUint(0, type(uint128).max);
        uint256 interestCutLimit = vm.randomUint(0, 1e18 - 1);

        vm.prank(morphoV2.feeSetter());
        vm.recordLogs();
        morphoV2.setTradingFee(id, tradingFee, interestCutLimit);
        (, bytes memory data) = findFirstEvent(address(morphoV2), EventsLib.SetTradingFee.selector);
        (uint256 eventTradingFee, uint256 eventInterestCutLimit) = abi.decode(data, (uint256, uint256));

        (uint256 newTradingFee, uint256 newInterestCutLimit) = morphoV2.tradingFeeParams(id);

        assertEq(eventTradingFee, newTradingFee, "trading fee");
        assertEq(eventInterestCutLimit, newInterestCutLimit, "interest cut limit");
    }

    function testSetTradingFeeRecipientEvent(address newRecipient) public {
        vm.recordLogs();
        morphoV2.setTradingFeeRecipient(newRecipient);
        (bytes32[] memory topics,) = findFirstEvent(address(morphoV2), EventsLib.SetTradingFeeRecipient.selector);
        address eventRecipient = address(uint160(uint256(topics[1])));

        assertEq(morphoV2.tradingFeeRecipient(), eventRecipient, "recipient state");
    }

    function testConsumeEvent(uint256 seed) public {
        vm.setSeed(seed);

        bytes32 group = bytes32(vm.randomUint());
        uint256 amount = vm.randomUint(1, 1e18);
        uint256 consumedBefore = vm.randomUint(0, 1e18);
        writeConsumed(address(this), group, consumedBefore);

        vm.recordLogs();
        morphoV2.consume(group, amount);
        (, bytes memory data) = findFirstEvent(address(morphoV2), EventsLib.Consume.selector);
        (uint256 eventAmount) = abi.decode(data, (uint256));

        assertEq(morphoV2.consumed(address(this), group), consumedBefore + eventAmount, "amount state");
    }

    function testShuffleSessionEvent(address user) public {
        vm.recordLogs();
        vm.prank(user);
        morphoV2.shuffleSession();
        (, bytes memory data) = findFirstEvent(address(morphoV2), EventsLib.ShuffleSession.selector);
        (bytes32 eventSession) = abi.decode(data, (bytes32));

        assertEq(eventSession, morphoV2.session(user), "session");
    }

    function testSupplyCollateralEvent(uint256 seed, address onBehalf) public {
        vm.setSeed(seed);

        deal(address(collateralToken1), address(morphoV2), 10e18);
        uint256 collateralBefore = vm.randomUint(0, 10e18);
        writeCollateral(onBehalf, address(collateralToken1), collateralBefore);

        uint256 assets = vm.randomUint(0, 10e18);

        deal(address(collateralToken1), address(this), assets);
        ERC20(address(collateralToken1)).approve(address(morphoV2), assets);

        vm.recordLogs();
        morphoV2.supplyCollateral(obligation, address(collateralToken1), assets, onBehalf);
        (, bytes memory data) = findFirstEvent(address(morphoV2), EventsLib.SupplyCollateral.selector);
        (, uint256 eventAssets) = abi.decode(data, (address, uint256));

        assertEq(
            morphoV2.collateralOf(onBehalf, id, address(collateralToken1)),
            collateralBefore + eventAssets,
            "collateral balance"
        );
    }

    function testWithdrawCollateralEvent(uint256 seed, address onBehalf) public {
        vm.setSeed(seed);

        deal(address(collateralToken1), address(morphoV2), 10e18);
        uint256 collateralBefore = vm.randomUint(0, 10e18);
        writeCollateral(onBehalf, address(collateralToken1), collateralBefore);

        uint256 assets = vm.randomUint(0, collateralBefore);

        vm.recordLogs();
        morphoV2.withdrawCollateral(obligation, address(collateralToken1), assets, onBehalf);
        (, bytes memory data) = findFirstEvent(address(morphoV2), EventsLib.WithdrawCollateral.selector);
        (, uint256 eventAssets) = abi.decode(data, (address, uint256));

        assertEq(
            morphoV2.collateralOf(onBehalf, id, address(collateralToken1)),
            collateralBefore - eventAssets,
            "collateral balance"
        );
    }

    function testLiquidateEvent(uint256 seed, address borrower) public {
        vm.setSeed(seed);

        uint256 debt = vm.randomUint(1e18, 5e18);

        deal(address(loanToken), address(liquidator), debt);

        uint256 totalUnitsBefore = debt + vm.randomUint(1e18, 5e18);
        uint256 withdrawableBefore = morphoV2.withdrawable(id);
        uint256 collateralBefore = debt * 1e18 / (2 * obligation.collaterals[0].lltv);

        writeWithdrawable(withdrawableBefore);
        writeDebt(borrower, debt);
        writeTotalUnits(totalUnitsBefore);
        writeCollateral(borrower, address(collateralToken1), collateralBefore);
        writeCollateral(borrower, address(collateralToken2), collateralBefore);
        deal(address(collateralToken1), address(morphoV2), 10e18);
        deal(address(collateralToken2), address(morphoV2), 10e18);

        Oracle(obligation.collaterals[0].oracle).setPrice(1e36 / 2);
        Oracle(obligation.collaterals[1].oracle).setPrice(1e36 / 4);

        Seizure[] memory seizures = new Seizure[](2);
        seizures[0] = Seizure({
            collateralIndex: 0, repaid: vm.randomUint(0, debt * obligation.collaterals[0].lltv / (1e18 * 4)), seized: 0
        });
        seizures[1] = Seizure({collateralIndex: 1, repaid: 0, seized: vm.randomUint(0, collateralBefore)});

        vm.recordLogs();
        vm.prank(liquidator);
        morphoV2.liquidate(obligation, seizures, borrower, "");
        (, bytes memory data) = findFirstEvent(address(morphoV2), EventsLib.Liquidate.selector);
        (Seizure[] memory eventSeizures, uint256 eventTotalRepaid, uint256 eventBadDebt) =
            abi.decode(data, (Seizure[], uint256, uint256));
        console.log(eventBadDebt);

        assertEq(morphoV2.withdrawable(id), withdrawableBefore + eventTotalRepaid, "withdrawable");
        assertEq(morphoV2.debtOf(borrower, id), debt - eventBadDebt - eventTotalRepaid, "debt");
        assertEq(morphoV2.totalUnits(id), totalUnitsBefore - eventBadDebt, "total units");
        // sort reverts the order
        assertEq(
            morphoV2.collateralOf(borrower, id, address(collateralToken1)),
            collateralBefore - eventSeizures[1].seized,
            "collateral 1"
        );
        assertEq(
            morphoV2.collateralOf(borrower, id, address(collateralToken2)),
            collateralBefore - eventSeizures[0].seized,
            "collateral 2"
        );
    }

    /* INTERNAL FUNCTIONS */

    function writeShares(address user, uint256 value) internal {
        store.target(address(morphoV2)).sig(morphoV2.sharesOf.selector).with_key(user).with_key(uint256(id))
            .checked_write(value);
    }

    function writeDebt(address user, uint256 value) internal {
        store.target(address(morphoV2)).sig(morphoV2.debtOf.selector).with_key(user).with_key(uint256(id))
            .checked_write(value);
    }

    function writeCollateral(address user, address token, uint256 value) internal {
        store.target(address(morphoV2)).sig(morphoV2.collateralOf.selector).with_key(user).with_key(uint256(id))
            .with_key(token).checked_write(value);
    }

    function writeTotalShares(uint256 value) internal {
        store.target(address(morphoV2)).sig(morphoV2.totalShares.selector).with_key(uint256(id)).checked_write(value);
    }

    function writeTotalUnits(uint256 value) internal {
        store.target(address(morphoV2)).sig(morphoV2.totalUnits.selector).with_key(uint256(id)).checked_write(value);
    }

    function writeWithdrawable(uint256 value) internal {
        store.target(address(morphoV2)).sig(morphoV2.withdrawable.selector).with_key(uint256(id)).checked_write(value);
    }

    function writeConsumed(address user, bytes32 group, uint256 value) internal {
        store.target(address(morphoV2)).sig(morphoV2.consumed.selector).with_key(user).with_key(group)
            .checked_write(value);
    }

    function setupState() internal {
        // Ensure always enough debt and shares to reduce them without underflow.
        writeShares(lender, vm.randomUint(3e18, 10e18));
        writeShares(otherLender, vm.randomUint(3e18, 10e18));
        writeTotalShares(morphoV2.sharesOf(lender, id) + morphoV2.sharesOf(otherLender, id));
        writeTotalUnits(vm.randomUint(0, morphoV2.totalShares(id)));
        writeWithdrawable(morphoV2.totalUnits(id));

        writeDebt(borrower, vm.randomUint(3e18, 10e18));
        writeDebt(otherBorrower, vm.randomUint(3e18, 10e18));

        deal(address(collateralToken1), address(morphoV2), 40e18);
        writeCollateral(borrower, address(collateralToken1), vm.randomUint(15e18, 20e18));
        writeCollateral(otherBorrower, address(collateralToken1), vm.randomUint(15e18, 20e18));

        deal(address(loanToken), address(morphoV2), 10e18);
        deal(address(loanToken), lender, 10e18);
        deal(address(loanToken), otherLender, 10e18);
        deal(address(loanToken), borrower, 10e18);
        deal(address(loanToken), otherBorrower, 10e18);
    }

    function findFirstEvent(address emitter, bytes32 selector)
        internal
        view
        returns (bytes32[] memory topics, bytes memory data)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == emitter && logs[i].topics[0] == selector) {
                topics = logs[i].topics;
                data = logs[i].data;
                break;
            }
        }
    }
}
