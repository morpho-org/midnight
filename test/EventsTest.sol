// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {stdStorage, StdStorage} from "../lib/forge-std/src/StdStorage.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {BaseTest} from "./BaseTest.sol";
import {Offer, Obligation, Collateral} from "../src/interfaces/IMorphoV2.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";
import "forge-std/console.sol";

struct TakeEventData {
    uint256 buyerAssets;
    uint256 sellerAssets;
    uint256 obligationUnits;
    uint256 obligationShares;
    Offer offer;
    uint256 buyerSharesIncrease;
    uint256 buyerDebtDecrease;
    uint256 sellerSharesDecrease;
    uint256 sellerDebtIncrease;
}

struct WithdrawEventData {
    uint256 obligationUnits;
    uint256 shares;
}

contract EventsTest is BaseTest {
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
        if (amountType == 0) offer.assets = vm.randomUint(1e18, 3e18);
        else if (amountType == 1) offer.obligationUnits = vm.randomUint(1e18, 3e18);
        else offer.obligationShares = vm.randomUint(1e18, 3e18);

        address buyer = vm.randomBool() ? lender : borrower;
        address seller = vm.randomBool() ? otherLender : otherBorrower;
        offer.maker = offer.buy ? buyer : seller;

        uint256 obligationShares = vm.randomUint(0, 1e18);

        uint256 consumedBefore = morphoV2.consumed(offer.maker, offer.group);
        uint256 totalSharesBefore = morphoV2.totalShares(id);
        uint256 totalUnitsBefore = morphoV2.totalUnits(id);
        uint256 buyerSharesBefore = morphoV2.sharesOf(buyer, id);
        uint256 sellerSharesBefore = morphoV2.sharesOf(seller, id);
        uint256 buyerDebtBefore = morphoV2.debtOf(buyer, id);
        uint256 sellerDebtBefore = morphoV2.debtOf(seller, id);

        vm.recordLogs();
        take(0, 0, 0, obligationShares, offer.buy ? seller : buyer, offer);
        (, bytes memory data) = findFirstEvent(address(morphoV2), EventsLib.Take.selector);
        (TakeEventData memory eventData) = abi.decode(bytes.concat(abi.encode(0x20), data), (TakeEventData));

        assertEq(
            morphoV2.totalShares(id),
            totalSharesBefore + eventData.buyerSharesIncrease - eventData.sellerSharesDecrease,
            "total shares"
        );
        assertEq(
            morphoV2.totalUnits(id),
            totalUnitsBefore + eventData.sellerDebtIncrease - eventData.buyerDebtDecrease,
            "total units"
        );
        assertEq(morphoV2.sharesOf(buyer, id), buyerSharesBefore + eventData.buyerSharesIncrease, "buyer shares");
        assertEq(morphoV2.sharesOf(seller, id), sellerSharesBefore - eventData.sellerSharesDecrease, "seller shares");
        assertEq(morphoV2.debtOf(buyer, id), buyerDebtBefore - eventData.buyerDebtDecrease, "buyer debt");
        assertEq(morphoV2.debtOf(seller, id), sellerDebtBefore + eventData.sellerDebtIncrease, "seller debt");
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
        WithdrawEventData memory eventData = abi.decode(data, (WithdrawEventData));

        assertEq(morphoV2.sharesOf(lender, id), sharesOfBefore - eventData.shares, "shares");
        assertEq(morphoV2.withdrawable(id), withdrawableBefore - eventData.obligationUnits, "withdrawable");
        assertEq(morphoV2.totalUnits(id), totalUnitsBefore - eventData.obligationUnits, "total units");
        assertEq(morphoV2.totalShares(id), totalSharesBefore - eventData.shares, "total shares");
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

    function setupState() internal {
        // Ensure always enough debt and shares to reduce them without underflow.
        writeShares(lender, vm.randomUint(3e18, 10e18));
        writeShares(otherLender, vm.randomUint(3e18, 10e18));
        writeTotalShares(morphoV2.sharesOf(lender, id) + morphoV2.sharesOf(otherLender, id));
        writeTotalUnits(vm.randomUint(0, morphoV2.totalShares(id)));
        writeWithdrawable(morphoV2.totalUnits(id));

        writeDebt(borrower, vm.randomUint(3e18, 10e18));
        writeDebt(otherBorrower, vm.randomUint(3e18, 10e18));

        writeCollateral(borrower, address(collateralToken1), 20e18);
        writeCollateral(otherBorrower, address(collateralToken1), 20e18);

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
